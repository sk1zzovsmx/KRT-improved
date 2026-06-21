local function keyTable(prefix)
    return setmetatable({}, {
        __index = function(t, key)
            local value = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
            rawset(t, key, value)
            return value
        end,
    })
end

local function makeFrame(shown, name)
    local frame = {
        _shown = shown ~= false,
        _name = name,
        _width = 320,
        _height = 240,
        _enabled = true,
    }

    function frame:IsShown()
        return self._shown
    end

    function frame:IsVisible()
        return self._shown
    end

    function frame:Show()
        self._shown = true
    end

    function frame:Hide()
        self._shown = false
    end

    function frame:GetName()
        return self._name
    end

    function frame:GetWidth()
        return self._width
    end

    function frame:SetWidth(width)
        self._width = width
    end

    function frame:SetAlpha(alpha)
        self._alpha = alpha
    end

    function frame:GetHeight()
        return self._height
    end

    function frame:SetHeight(height)
        self._height = height
    end

    function frame:GetNumRegions()
        return 0
    end

    function frame:GetRegions()
        return nil
    end

    function frame:UpdateScrollChildRect() end

    function frame:EnableKeyboard() end

    function frame:EnableMouse(enabled)
        self._mouseEnabled = enabled ~= false
    end

    function frame:IsEnabled()
        return self._enabled ~= false
    end

    function frame:Enable()
        self._enabled = true
    end

    function frame:Disable()
        self._enabled = false
    end

    function frame:RegisterForClicks() end

    function frame:RegisterForDrag() end

    function frame:SetScript(scriptType, callback)
        self[scriptType] = callback
    end

    function frame:HookScript(scriptType, callback)
        self["Hooked" .. tostring(scriptType)] = callback
    end

    function frame:ClearFocus()
        self._focused = false
    end

    function frame:SetFocus()
        self._focused = true
    end

    function frame:SetText(text)
        self.text = text
    end

    function frame:SetTextColor(r, g, b)
        self._textColor = { r, g, b }
    end

    function frame:SetNumber(value)
        self.text = tostring(value)
    end

    function frame:GetText()
        return self.text or ""
    end

    function frame:HighlightText(startPos, endPos)
        self._highlight = { startPos, endPos }
    end

    function frame:SetCursorPosition(pos)
        self._cursor = pos
    end

    function frame:SetAutoFocus() end

    function frame:SetMultiLine() end

    function frame:SetScrollChild(child)
        self._scrollChild = child
    end

    function frame:SetTextInsets(left, right, top, bottom)
        self._textInsets = { left, right, top, bottom }
    end

    function frame:SetJustifyH() end

    function frame:SetJustifyV() end

    function frame:SetWordWrap(value)
        self._wordWrap = value
    end

    function frame:SetFontObject() end

    function frame:GetStringHeight()
        return string.len(self.text or "")
    end

    function frame:SetParent(parent)
        self.parent = parent
    end

    function frame:ClearAllPoints()
        self._points = {}
        self._pointsCleared = true
    end

    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self._points = self._points or {}
        self._points[#self._points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end

    function frame:SetFrameLevel(level)
        self._frameLevel = level
    end

    function frame:GetFrameLevel()
        return self._frameLevel or 1
    end

    function frame:SetFrameStrata(strata)
        self._frameStrata = strata
    end

    function frame:GetFrameStrata()
        return self._frameStrata
    end

    function frame:SetToplevel(value)
        self._toplevel = value and true or false
    end

    function frame:SetID(id)
        self.id = id
    end

    function frame:GetID()
        return self.id
    end

    function frame:LockHighlight()
        self._highlighted = true
    end

    function frame:UnlockHighlight()
        self._highlighted = false
    end

    function frame:SetVertexColor(r, g, b)
        self._vertexColor = { r, g, b }
    end

    function frame:SetNormalTexture(texture)
        local normalTexture = self._normalTexture
        if not normalTexture then
            normalTexture = {
                texture = nil,
                desaturated = false,
                SetDesaturated = function(tex, value)
                    tex.desaturated = value and true or false
                end,
                SetVertexColor = function(tex, r, g, b)
                    tex._vertexColor = { r, g, b }
                end,
            }
            self._normalTexture = normalTexture
        end
        normalTexture.texture = texture
    end

    function frame:GetNormalTexture()
        if not self._normalTexture then
            self:SetNormalTexture(nil)
        end
        return self._normalTexture
    end

    return frame
end

local function makeBus()
    local callbacks = {}
    local triggered = {}
    local bus = {}

    function bus.RegisterCallback(eventName, callback)
        if not eventName or type(callback) ~= "function" then
            return
        end
        local list = callbacks[eventName]
        if not list then
            list = {}
            callbacks[eventName] = list
        end
        list[#list + 1] = callback
    end

    function bus.TriggerEvent(eventName, ...)
        triggered[eventName] = (triggered[eventName] or 0) + 1
        local list = callbacks[eventName]
        if not list then
            return
        end
        for i = 1, #list do
            list[i](eventName, ...)
        end
    end

    bus._callbacks = callbacks
    bus._triggered = triggered
    return bus
end

local function installTableHelpers()
    if not table.wipe then
        function table.wipe(t)
            for key in pairs(t) do
                t[key] = nil
            end
            return t
        end
    end
end

local function wrapServiceMethods(tbl, methodNames)
    if type(tbl) ~= "table" then
        return tbl
    end

    for i = 1, #methodNames do
        local key = methodNames[i]
        local fn = tbl[key]
        if type(fn) == "function" then
            tbl[key] = function(_, ...)
                return fn(...)
            end
        end
    end

    return tbl
end

local function reservesApi(tbl)
    return wrapServiceMethods(tbl, {
        "GetReserveCountForItem",
        "GetItemReserveContext",
        "GetPlusForItem",
        "GetPlayersForItem",
        "HasCurrentRaidPlayersForItem",
        "GetImportMode",
        "IsPlusSystem",
    })
end

local function rollsApi(tbl)
    tbl = tbl or {}

    if type(tbl.ValidateWinner) ~= "function" then
        function tbl:ValidateWinner()
            return { ok = true, reason = nil }
        end
    end

    if type(tbl.GetRolls) ~= "function" then
        function tbl:GetRolls()
            return {}
        end
    end

    if type(tbl.GetDisplayedWinner) ~= "function" then
        function tbl:GetDisplayedWinner(preferredWinner, model)
            if preferredWinner and preferredWinner ~= "" then
                return preferredWinner
            end
            return model and model.winner or nil
        end
    end

    if type(tbl.GetResolvedWinner) ~= "function" then
        function tbl:GetResolvedWinner(model)
            return model and model.winner or nil
        end
    end

    if type(tbl.ShouldUseTieReroll) ~= "function" then
        function tbl:ShouldUseTieReroll(model)
            local resolution = model and model.resolution or nil
            local requiredWinnerCount = tonumber(model and model.requiredWinnerCount) or 1
            local selectedCount = tonumber(model and model.msCount) or 0
            return resolution and resolution.requiresManualResolution == true and requiredWinnerCount == 1 and selectedCount <= 0
        end
    end

    if type(tbl.SetExpectedWinners) ~= "function" then
        function tbl:SetExpectedWinners(count)
            return count
        end
    end

    if type(tbl.EnsureRollSession) ~= "function" then
        function tbl:EnsureRollSession(itemLink, rollType, source)
            self._session = self._session or {}
            self._session.itemLink = itemLink
            self._session.rollType = rollType
            self._session.source = source
            self._session.id = self._session.id or "test-session"
            self._session.lootNid = tonumber(self._session.lootNid) or 0
            return self._session
        end
    end

    if type(tbl.EnsureLootRollSession) ~= "function" then
        function tbl:EnsureLootRollSession(itemLink, rollType, source, _opts)
            return self:EnsureRollSession(itemLink, rollType, source)
        end
    end

    if type(tbl.SyncSessionState) ~= "function" then
        function tbl:SyncSessionState(_session)
            return nil
        end
    end

    if type(tbl.IsCountdownRunning) ~= "function" then
        function tbl:IsCountdownRunning()
            return self._countdownRunning == true
        end
    end

    if type(tbl.StopCountdown) ~= "function" then
        function tbl:StopCountdown()
            self._countdownRunning = false
        end
    end

    if type(tbl.StartCountdown) ~= "function" then
        function tbl:StartCountdown(_duration, _onTick, _onComplete)
            self._countdownRunning = true
            return true
        end
    end

    if type(tbl.FinalizeRollSession) ~= "function" then
        function tbl:FinalizeRollSession()
            self._countdownRunning = false
        end
    end

    return tbl
end

local function raidApi(tbl)
    tbl = tbl or {}

    if type(tbl.GetPlayerClass) ~= "function" then
        function tbl:GetPlayerClass()
            return "UNKNOWN"
        end
    end

    if type(tbl.CheckPlayer) ~= "function" then
        function tbl:CheckPlayer(name)
            return true, name
        end
    end

    if type(tbl.GetRosterVersion) ~= "function" then
        function tbl:GetRosterVersion()
            return 0
        end
    end

    if type(tbl.RequestMasterLootCandidateRefresh) ~= "function" then
        function tbl:RequestMasterLootCandidateRefresh()
            return nil
        end
    end

    if type(tbl.FindMasterLootCandidateIndex) ~= "function" then
        function tbl:FindMasterLootCandidateIndex()
            return nil
        end
    end

    if type(tbl.CanResolveMasterLootCandidates) ~= "function" then
        function tbl:CanResolveMasterLootCandidates()
            return false
        end
    end

    if type(tbl.MatchHeldInventoryLoot) ~= "function" then
        function tbl:MatchHeldInventoryLoot(entry)
            return type(entry) == "table" and tonumber(entry.rollType) == 7
        end
    end

    if type(tbl.ResolveHeldLootNid) ~= "function" then
        function tbl:ResolveHeldLootNid(itemLink, preferredLootNid, holderName, raidNum)
            local preferred = tonumber(preferredLootNid) or 0
            if preferred > 0 and type(self.GetLootByNid) == "function" then
                local entry = self:GetLootByNid(preferred, raidNum)
                if self:MatchHeldInventoryLoot(entry, raidNum, itemLink, holderName) then
                    return preferred
                end
            end

            if type(self.GetHeldLootNid) == "function" then
                return tonumber(self:GetHeldLootNid(itemLink, raidNum, holderName, 0)) or 0
            end

            return 0
        end
    end

    return tbl
end

local function chatApi(tbl)
    tbl = tbl or {}

    if type(tbl.AnnounceWarningMessage) ~= "function" then
        function tbl:AnnounceWarningMessage(_content)
            return true
        end
    end

    if type(tbl.GetSpamRuntimeState) ~= "function" then
        function tbl:GetSpamRuntimeState()
            self._spamRuntime = self._spamRuntime
                or {
                    ticking = false,
                    paused = false,
                    countdownRemaining = 0,
                    runElapsedSeconds = 0,
                    messagesSent = 0,
                    durationSeconds = 60,
                }
            return self._spamRuntime
        end
    end

    if type(tbl.StartSpamCycle) ~= "function" then
        function tbl:StartSpamCycle(config)
            local runtime = self:GetSpamRuntimeState()
            runtime.ticking = true
            runtime.paused = false
            runtime.durationSeconds = tonumber(config and config.duration) or runtime.durationSeconds
            runtime.countdownRemaining = runtime.durationSeconds
            return true, runtime
        end
    end

    if type(tbl.StopSpamCycle) ~= "function" then
        function tbl:StopSpamCycle(resetCountdown, resetRun)
            local runtime = self:GetSpamRuntimeState()
            runtime.ticking = false
            runtime.paused = false
            if resetCountdown then
                runtime.countdownRemaining = 0
            end
            if resetRun then
                runtime.runElapsedSeconds = 0
                runtime.messagesSent = 0
            end
            return runtime
        end
    end

    if type(tbl.PauseSpamCycle) ~= "function" then
        function tbl:PauseSpamCycle()
            local runtime = self:GetSpamRuntimeState()
            if not runtime.ticking or runtime.paused then
                return false, runtime
            end
            runtime.paused = true
            return true, runtime
        end
    end

    return tbl
end

local function newHarness()
    installTableHelpers()
    _G.KRT_Options = nil

    local logs = {
        error = {},
        warn = {},
        info = {},
        debug = {},
        trace = {},
    }
    local timers = {}
    local itemRegistry = {}
    local raidRoleOverride = nil
    local raidCapabilityOverrides = {}

    local function pushLog(bucket, message)
        logs[bucket][#logs[bucket] + 1] = tostring(message)
    end

    local function copyTable(tbl)
        local copy = {}
        for key, value in pairs(tbl or {}) do
            copy[key] = value
        end
        return copy
    end

    local L = keyTable("L")
    local Diag = {
        D = keyTable("Diag.D"),
        I = keyTable("Diag.I"),
        W = keyTable("Diag.W"),
        E = keyTable("Diag.E"),
    }
    L.StrRollTieTag = "TIE"
    L.StrRollPassTag = "PASS"
    L.StrRollCancelledTag = "CXL"
    L.StrRollTimedOutTag = "OOT"
    L.StrRollOutTag = "OUT"
    L.StrRollBlockedTag = "BLK"
    L.StrRollDuplicateTag = "DUP"
    L.StrRollRerollOnlyTag = "REROLL"
    L.StrRollSrSummaryPresentMissing = "SR %d present / %d missing"
    L.StrRollSrSummaryPresent = "SR %d present"
    L.StrRollSrSummaryNoPresent = "No present SR"
    L.StrRollSrSummaryFallback = "Free roll fallback"
    L.StrRollLootCopies = "Copies: %d"
    Diag.E.LogLoggerLootNidExpected = "[Logger] loot entry expected lootNid but got raw itemId raidId=%s value=%s link=%s matches=%d"
    local InternalEvents = keyTable("Event")
    local Events = { Internal = InternalEvents }
    local rollTypes = {
        MANUAL = 0,
        MAINSPEC = 1,
        OFFSPEC = 2,
        RESERVED = 3,
        FREE = 4,
        BANK = 5,
        DISENCHANT = 6,
        HOLD = 7,
        NEED = 8,
        GREED = 9,
    }
    local C = {
        ITEM_LINK_PATTERN = "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?" .. "(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?",
        BOSS_KILL_DEDUPE_WINDOW_SECONDS = 30,
        BOSS_EVENT_CONTEXT_TTL_SECONDS = 30,
        PENDING_AWARD_TTL_SECONDS = 8,
        GROUP_LOOT_PENDING_AWARD_TTL_SECONDS = 60,
        GROUP_LOOT_ROLL_GRACE_SECONDS = 10,
        RECENT_LOOT_DEATH_CONTEXT_TTL_SECONDS = 8,
        RESERVES_ITEM_FALLBACK_ICON = "fallback-icon",
        RESERVES_QUERY_COOLDOWN_SECONDS = 2,
        CLASS_COLORS = {},
        RAID_TARGET_MARKERS = {
            "{circle}",
            "{diamond}",
            "{triangle}",
            "{moon}",
            "{square}",
            "{cross}",
            "{skull}",
        },
        rollTypes = rollTypes,
    }

    local Bus = makeBus()
    local Strings = {}
    function Strings.TrimText(value, allowNil)
        if value == nil then
            return allowNil and nil or ""
        end
        return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    end

    function Strings.NilIfEmpty(value)
        local out = Strings.TrimText(value, true)
        if out == nil or out == "" then
            return nil
        end
        return out
    end

    function Strings.NormalizeText(value, allowNil)
        local out = Strings.TrimText(value, allowNil)
        if allowNil and out == "" then
            return nil
        end
        return out
    end

    function Strings.NormalizeName(name, allowNil)
        local out = Strings.TrimText(name, allowNil)
        if out == nil then
            return nil
        end
        return out
    end

    function Strings.NormalizeLower(name, allowNil)
        local out = Strings.NormalizeName(name, allowNil)
        return out and string.lower(out) or nil
    end

    function Strings.GetNormalizedNameLower(value)
        return Strings.NormalizeLower(value, true)
    end

    function Strings.SplitArgs(value)
        value = tostring(value or "")
        local first, rest = value:match("^%s*(%S+)%s*(.-)%s*$")
        return first or "", rest or ""
    end

    local function splitPayloadFields(text, sep, out)
        local fields = out or {}
        local delimiter = tostring(sep or "|")
        local input = tostring(text or "")
        local n = 0
        local startPos = 1

        while true do
            local fromPos, toPos = input:find(delimiter, startPos, true)
            if not fromPos then
                n = n + 1
                fields[n] = input:sub(startPos)
                break
            end
            n = n + 1
            fields[n] = input:sub(startPos, fromPos - 1)
            startPos = toPos + 1
        end

        for i = n + 1, #fields do
            fields[i] = nil
        end

        return fields, n
    end

    local function packPayloadFields(sep, ...)
        local n = select("#", ...)
        local out = {}
        for i = 1, n do
            out[i] = tostring(select(i, ...) or "")
        end
        return table.concat(out, tostring(sep or "|"))
    end

    local function isBossFightRecord(boss)
        if type(boss) ~= "table" then
            return false
        end
        local sourceKind = boss.sourceKind
        if sourceKind == "shared" or sourceKind == "trash" or sourceKind == "object" then
            return false
        end
        if boss.source == "LootSources" then
            return false
        end
        local name = boss.name or boss.boss
        if type(name) == "string" and name:sub(1, 7) == "Shared:" then
            return false
        end
        return true
    end

    local Sort = {
        CompareValues = function(a, b)
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        CompareNumbers = function(a, b)
            a = tonumber(a) or 0
            b = tonumber(b) or 0
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        CompareStrings = function(a, b)
            a = tostring(a or "")
            b = tostring(b or "")
            if a == b then
                return 0
            end
            return (a < b) and -1 or 1
        end,
        GetLootSortName = function(loot)
            return loot and (loot.itemName or loot.itemLink or "") or ""
        end,
        CompareLootTie = function(a, b)
            return (tonumber(a and a.lootNid) or 0) < (tonumber(b and b.lootNid) or 0)
        end,
    }

    local servicesStore = {}
    local services = setmetatable({}, {
        __index = servicesStore,
        __newindex = function(_, key, value)
            if key == "Reserves" then
                value = reservesApi(value)
            elseif key == "Rolls" then
                value = rollsApi(value)
            elseif key == "Raid" then
                value = raidApi(value)
            elseif key == "Chat" then
                value = chatApi(value)
            end
            rawset(servicesStore, key, value)
        end,
    })

    services.Loot = {
        RemovePendingAward = function()
            return nil
        end,
    }
    services.Rolls = {
        GetHighestRoll = function()
            return 0
        end,
        GetRollSession = function()
            return nil
        end,
        GetRollStatus = function()
            return nil, false, false, false
        end,
        SyncSessionState = function() end,
    }
    services.Raid = {}
    services.Chat = {}

    local addon = {
        State = { debugEnabled = true, raidStore = {}, currentRaid = 1, lastBoss = 0 },
        options = { srImportMode = 0 },
        Controllers = {},
        Services = services,
        Widgets = {},
        DB = {},
        UI = {
            Widgets = {},
            Primitives = {},
            Rows = {},
            Scaffold = {},
            Frames = {},
            Lists = {},
            Selection = {},
            Effects = {},
            Layout = {},
            EditBoxes = {},
            Popups = {},
            Tooltips = {},
        },
        Colors = {},
        Base64 = {},
        C = C,
        L = L,
        Diag = Diag,
        Events = Events,
        Strings = Strings,
        Sort = Sort,
    }

    addon.debug = function(_, message)
        pushLog("debug", message)
    end
    addon.info = function(_, message)
        pushLog("info", message)
    end
    addon.warn = function(_, message)
        pushLog("warn", message)
    end
    addon.error = function(_, message)
        pushLog("error", message)
    end
    addon.trace = function(_, message)
        pushLog("trace", message)
    end
    addon.Base64.Encode = function(value)
        return tostring(value):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A")
    end
    addon.Base64["Decode"] = function(value)
        return tostring(value):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
    end
    addon.WrapTextInColorCode = tostring
    addon.Colors.NormalizeHexColor = tostring
    addon.Services.Chat = addon.Services.Chat or {}
    local announceMethod = "Announce"
    addon.Services.Chat[announceMethod] = function(_, message)
        pushLog("info", message)
    end
    function addon.Services.Chat:ShowMasterOnlyWarning()
        pushLog("warn", L.WarnMLOnlyMode or L.WarnMLNoPermission)
    end

    local function getRaidService()
        return addon.Services and addon.Services.Raid or nil
    end

    local function deriveRaidRank()
        if type(addon.UnitIsGroupLeader) == "function" and addon.UnitIsGroupLeader("player") then
            return 2
        end
        if type(addon.UnitIsGroupAssistant) == "function" and addon.UnitIsGroupAssistant("player") then
            return 1
        end
        return 0
    end

    local function buildRaidRoleState()
        local raidService = getRaidService()
        local inRaid = raidService and type(raidService.IsPlayerInRaid) == "function" and raidService:IsPlayerInRaid() or false
        local rank = deriveRaidRank()
        local isMasterLooter = raidService and type(raidService.IsMasterLooter) == "function" and raidService:IsMasterLooter() or false

        if type(raidRoleOverride) == "table" then
            if raidRoleOverride.inRaid ~= nil then
                inRaid = raidRoleOverride.inRaid == true
            end
            if raidRoleOverride.rank ~= nil then
                rank = tonumber(raidRoleOverride.rank) or 0
            elseif raidRoleOverride.isLeader == true then
                rank = 2
            elseif raidRoleOverride.isAssistant == true then
                rank = 1
            end
            if raidRoleOverride.isMasterLooter ~= nil then
                isMasterLooter = raidRoleOverride.isMasterLooter == true
            end
        end

        return {
            inRaid = inRaid,
            rank = rank,
            isLeader = rank >= 2,
            isAssistant = rank == 1,
            hasRaidLeadership = inRaid and rank > 0,
            hasGroupLeadership = rank > 0,
            isMasterLooter = isMasterLooter,
        }
    end

    addon.Services.Raid = addon.Services.Raid or {}
    local raid = addon.Services.Raid

    function raid:GetPlayerRoleState()
        return buildRaidRoleState()
    end

    function raid:GetCapabilityState(capability)
        local role = self:GetPlayerRoleState()
        local override = raidCapabilityOverrides[capability]
        if override ~= nil then
            local allowed = false
            local reason
            if type(override) == "table" then
                allowed = override.allowed == true
                reason = override.reason
            else
                allowed = override == true
            end
            if not allowed and reason == nil then
                reason = "override_denied"
            end
            return {
                capability = capability,
                allowed = allowed,
                reason = reason,
                role = role,
            }
        end

        local state = {
            capability = capability,
            allowed = false,
            reason = "unknown_capability",
            role = role,
        }

        if capability == "loot" then
            if not role.inRaid or role.isMasterLooter then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_master_looter"
            end
            return state
        end

        if capability == "inventory_trade" then
            if not role.inRaid or role.isMasterLooter or role.hasRaidLeadership then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_loot_or_leadership"
            end
            return state
        end

        if capability == "raid_leadership" or capability == "loot_counter_broadcast" or capability == "raid_warning" or capability == "raid_icons" then
            if not role.inRaid then
                state.reason = "not_in_raid"
            elseif role.hasRaidLeadership then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_leadership"
            end
            return state
        end

        if capability == "group_leadership" or capability == "ready_check" then
            if role.hasGroupLeadership then
                state.allowed = true
                state.reason = nil
            else
                state.reason = "missing_group_leadership"
            end
            return state
        end

        return state
    end

    function raid:CanUseCapability(capability)
        local state = self:GetCapabilityState(capability)
        return state and state.allowed == true
    end

    function raid:EnsureMasterOnlyAccess()
        if not self:CanUseCapability("loot") then
            addon.Services.Chat:ShowMasterOnlyWarning()
            return false
        end
        return true
    end

    local function ensureCanonicalChatService()
        addon.Services.Chat = addon.Services.Chat or {}
        local chat = addon.Services.Chat
        chat.Announce = chat.Announce or function(_, message)
            pushLog("info", message)
        end
        chat.ShowMasterOnlyWarning = chat.ShowMasterOnlyWarning or function()
            pushLog("warn", L.WarnMLOnlyMode or L.WarnMLNoPermission)
        end
        return chat
    end

    local function ensureCanonicalRaidCapabilityService()
        addon.Services.Raid = addon.Services.Raid or {}
        local currentRaid = addon.Services.Raid

        currentRaid.GetPlayerRoleState = currentRaid.GetPlayerRoleState or function()
            return buildRaidRoleState()
        end
        currentRaid.GetCapabilityState = currentRaid.GetCapabilityState
            or function(self, capability)
                local role = self:GetPlayerRoleState()
                return {
                    capability = capability,
                    allowed = true,
                    reason = nil,
                    role = role,
                }
            end
        currentRaid.CanUseCapability = currentRaid.CanUseCapability
            or function(self, capability)
                local state = self:GetCapabilityState(capability)
                return state and state.allowed == true
            end
        currentRaid.EnsureMasterOnlyAccess = currentRaid.EnsureMasterOnlyAccess
            or function(self)
                if not self:CanUseCapability("loot") then
                    ensureCanonicalChatService():ShowMasterOnlyWarning()
                    return false
                end
                return true
            end

        return currentRaid
    end

    addon.tLength = function(tbl)
        local count = 0
        for _ in pairs(tbl or {}) do
            count = count + 1
        end
        return count
    end

    addon.GetClassColor = function()
        return nil, nil, nil, "ffffffff"
    end

    addon.UnitIterator = function()
        return function()
            return nil
        end
    end

    addon.NewTimer = function(delay, callback)
        local timer = {
            delay = delay,
            callback = callback,
            cancelled = false,
        }
        timers[#timers + 1] = timer
        return timer
    end

    addon.NewTicker = function(delay, callback, iterations)
        local ticker = {
            delay = delay,
            callback = callback,
            iterations = iterations or 1,
            cancelled = false,
        }
        timers[#timers + 1] = ticker
        return ticker
    end

    addon.CancelTimer = function(timer)
        if timer then
            timer.cancelled = true
        end
    end

    addon.After = function(delay, callback)
        return addon.NewTimer(delay, callback)
    end

    -- Test stub for addon.Timer mixins: reuse the existing `timers` infrastructure.
    -- Map ScheduleTimer/ScheduleRepeatingTimer/CancelTimer so _flushTimers continues to work.
    addon.Timer = {
        BindMixin = function(target)
            if target.ScheduleTimer then
                return target
            end
            target._timerActive = target._timerActive or {}
            target.ScheduleTimer = function(self, callback, delay, ...)
                local n = select("#", ...)
                local args = (n > 0) and { ... } or nil
                -- Forward declare handle: the inner closure references it, and in
                -- Lua 5.1 `local x = f(function() ... x ... end)` captures `x`
                -- as a global (nil), so it must be declared first.
                local handle
                handle = addon.NewTimer(delay, function()
                    self._timerActive[handle] = nil
                    if args then
                        callback(unpack(args, 1, n))
                    else
                        callback()
                    end
                end)
                self._timerActive[handle] = true
                return handle
            end
            target.ScheduleRepeatingTimer = function(self, callback, interval, ...)
                local n = select("#", ...)
                local args = (n > 0) and { ... } or nil
                local handle
                handle = addon.NewTicker(interval, function()
                    if args then
                        callback(unpack(args, 1, n))
                    else
                        callback()
                    end
                end)
                self._timerActive[handle] = true
                return handle
            end
            target.CancelTimer = function(self, handle)
                if handle and self._timerActive[handle] then
                    self._timerActive[handle] = nil
                    addon.CancelTimer(handle)
                    return true
                end
                return false
            end
            return target
        end,
        RefreshStats = function() end,
        ShowStats = function() end,
    }

    addon._flushTimers = function()
        local pending = timers
        timers = {}
        for i = 1, #pending do
            local timer = pending[i]
            if not timer.cancelled and type(timer.callback) == "function" then
                timer.callback(timer)
            end
        end
    end

    addon._timerCount = function()
        local active = 0
        for i = 1, #timers do
            if not timers[i].cancelled then
                active = active + 1
            end
        end
        return active
    end

    local widgetRegistry = {}
    addon.UI.Widgets = {
        IsEnabled = function()
            return true
        end,
        IsRegistered = function(_, widgetId)
            return widgetRegistry[widgetId] ~= nil
        end,
        Register = function(widgetId, api)
            widgetRegistry[widgetId] = api
            return true
        end,
        Call = function(widgetId, methodName, ...)
            local api = widgetRegistry[widgetId]
            local fn = api and api[methodName] or nil
            if type(fn) == "function" then
                return fn(...)
            end
            return nil
        end,
    }

    addon.UI.Primitives.SetEnabled = function(frame, enabled)
        if frame then
            frame._enabled = enabled and true or false
        end
    end

    addon.UI.Primitives.SetButtonGlow = function(frame, enabled)
        if frame then
            frame._glow = enabled and true or false
        end
    end

    addon.UI.Primitives.Toggle = function(frame)
        if not frame then
            return
        end
        if frame:IsVisible() then
            frame:Hide()
        else
            frame:Show()
        end
    end

    addon.UI.Primitives.SetShown = function(frame, shown)
        if not frame then
            return
        end
        if shown then
            frame:Show()
        else
            frame:Hide()
        end
    end

    addon.UI.Rows = {
        EnsureVisuals = function() end,
        SetSelected = function() end,
        SetFocused = function() end,
        DrawMasterRollRow = function(row, data, onClick)
            if not row or not data then
                return
            end
            row.playerName = data.name
            if row.EnableMouse then
                row:EnableMouse(data.canClick == true)
            end
            if type(onClick) == "function" then
                if row.SetScript then
                    row:SetScript("OnClick", onClick)
                else
                    row.OnClick = onClick
                end
            end
        end,
    }

    addon.Comms = {
        Payload = {
            EncodeText = addon.Base64.Encode,
            DecodeText = addon.Base64.Decode,
            SplitFields = splitPayloadFields,
            PackFields = packPayloadFields,
        },
        Sync = function() end,
        Whisper = function() end,
    }
    addon.Comms._Payload = addon.Comms.Payload

    addon.Item = {
        GetItemIdFromLink = function(value)
            if type(value) == "number" then
                return value
            end
            if type(value) ~= "string" then
                return nil
            end
            return tonumber(value:match("item:(%-?%d+)"))
        end,
        GetItemStringFromLink = function(value)
            if type(value) ~= "string" then
                return nil
            end
            return value:match("|H([^|]+)|h")
        end,
    }

    local moduleStateStore = setmetatable({}, { __mode = "k" })
    addon.UI.ModuleState = {
        Ensure = function(module)
            moduleStateStore[module] = moduleStateStore[module]
                or {
                    Loaded = false,
                    Bound = false,
                    Localized = false,
                    Dirty = true,
                    Reason = nil,
                    FrameName = nil,
                }
            return moduleStateStore[module]
        end,
        Get = function(module)
            return moduleStateStore[module]
        end,
    }
    addon.UI.Scaffold = {
        EnsureModuleState = function(module)
            return addon.UI.ModuleState.Ensure(module)
        end,
        DefineModule = function() end,
        CreateWidgetApi = function(_, api)
            return api or {}
        end,
    }

    addon.UI.Frames = {
        Get = function(name)
            return _G[name]
        end,
        Ref = function(frame, suffix)
            if not frame or not frame.GetName then
                return nil
            end
            return _G[(frame:GetName() or "") .. suffix]
        end,
        GetRef = function(frame, suffix)
            if not frame or not frame.GetName then
                return nil
            end
            return _G[(frame:GetName() or "") .. suffix]
        end,
        SetShown = function(frame, shown)
            if frame then
                frame._shown = shown and true or false
            end
        end,
        BindModuleFrame = function(module, frame)
            module.frame = frame
            return frame and frame.GetName and frame:GetName() or "TestFrame"
        end,
        SetFrameTitle = function() end,
        SetScriptSafely = function(frame, scriptType, callback)
            if frame then
                frame[scriptType] = callback
            end
        end,
        GetNamedParts = function(widget, parts, cacheField)
            if not widget or type(parts) ~= "table" then
                return nil
            end

            cacheField = cacheField or "_krtRefs"
            if widget[cacheField] then
                return widget[cacheField]
            end

            local widgetName = widget.GetName and widget:GetName() or nil
            local refs = {}

            for key, suffix in pairs(parts) do
                local refKey = type(key) == "number" and suffix or key
                refs[refKey] = widgetName and _G[widgetName .. suffix] or nil
            end

            widget[cacheField] = refs
            return refs
        end,
        MakeFrameGetter = function(name)
            return function()
                return _G[name]
            end
        end,
        GetButtonPopup = function(cfg)
            local popup = {
                frame = nil,
                buttons = {},
            }

            local function resolveParent()
                if type(cfg.getParent) == "function" then
                    return cfg.getParent()
                end
                return cfg.parent
            end

            local function ensureFrame()
                if popup.frame then
                    return popup.frame
                end

                local parent = resolveParent()
                if not parent then
                    return nil
                end

                popup.frame = _G.CreateFrame("Frame", cfg.frameName, parent, cfg.frameTemplate)
                popup.frame:Hide()
                return popup.frame
            end

            local function ensureButton(index)
                local frame = ensureFrame()
                if not frame then
                    return nil
                end

                local button = popup.buttons[index]
                if button then
                    return button
                end

                local buttonName = cfg.buttonName and cfg.buttonName(index) or nil
                button = _G.CreateFrame("Button", buttonName, frame, cfg.buttonTemplate)
                button:SetID(index)
                if button.RegisterForClicks then
                    button:RegisterForClicks(cfg.clickRegistration or "AnyUp")
                end
                if cfg.onButtonClick then
                    button.OnClick = cfg.onButtonClick
                end

                popup.buttons[index] = button
                return button
            end

            function popup:GetFrame()
                return self.frame or ensureFrame()
            end

            function popup:Hide()
                if self.frame then
                    self.frame:Hide()
                end
            end

            function popup:Toggle()
                local frame = ensureFrame()
                if not frame then
                    return false
                end

                if frame:IsShown() then
                    frame:Hide()
                else
                    frame:Show()
                end

                return frame:IsShown()
            end

            function popup:Refresh(count)
                local frame = ensureFrame()
                local rowCount = tonumber(count) or 0
                local height = tonumber(cfg.topInset) or 5
                local rowStep = tonumber(cfg.rowStep) or 37

                if not frame then
                    return nil
                end

                for index = 1, rowCount do
                    local button = ensureButton(index)
                    if button then
                        if cfg.drawButton then
                            cfg.drawButton(button, index)
                        end
                        button:Show()
                        height = height + rowStep
                    end
                end

                for index = rowCount + 1, #self.buttons do
                    local button = self.buttons[index]
                    if button then
                        button:Hide()
                    end
                end

                frame:SetHeight(height)
                if rowCount <= 0 then
                    frame:Hide()
                end

                return frame
            end

            return popup
        end,
    }

    addon.UI.Popups.DefineEditBox = function(name, _, onAccept, onShow, validate)
        _G[name] = {
            onAccept = onAccept,
            onShow = onShow,
            validate = validate,
        }
    end

    addon.UI.Popups.DefineConfirm = function(name, text, onAccept)
        _G[name] = {
            text = text,
            onAccept = onAccept,
        }
    end

    addon.UI.Tooltips.Bind = function() end

    addon.UI.EditBoxes.SetValue = function(editBox, value)
        if editBox and editBox.SetText then
            editBox:SetText(tostring(value or ""))
        end
    end

    addon.UI.EditBoxes.BindHandlers = function(frameName, specs, requestRefreshFn)
        if type(frameName) ~= "string" or type(specs) ~= "table" then
            return
        end

        for i = 1, #specs do
            local spec = specs[i]
            local suffix = spec and spec.suffix
            local editBox = suffix and _G[frameName .. suffix] or nil
            if editBox then
                if spec.onEscape then
                    editBox.OnEscapePressed = spec.onEscape
                end
                if spec.onEnter then
                    editBox.OnEnterPressed = spec.onEnter
                end
                if spec.onFocusLost then
                    editBox.OnEditFocusLost = spec.onFocusLost
                end
                if requestRefreshFn then
                    editBox.OnTextChanged = function(_, isUserInput)
                        if isUserInput then
                            requestRefreshFn()
                        end
                    end
                end
            end
        end
    end

    addon.UI.EditBoxes.Reset = function(editBox)
        if editBox and editBox.SetText then
            editBox:SetText("")
        end
    end

    addon.UI.Lists = {
        CreateRowRenderer = function(fn)
            return function(row, it)
                return fn(row, it)
            end
        end,
        MakeIndexedRowName = function(suffix)
            suffix = tostring(suffix or "")
            return function(frameName, _, index)
                return tostring(frameName or "") .. suffix .. tostring(index or "")
            end
        end,
        CreateController = function(cfg)
            local controller = { cfg = cfg, dirtyCount = 0 }
            function controller:Dirty()
                self.dirtyCount = self.dirtyCount + 1
            end

            function controller:Touch()
                self:Dirty()
            end

            return controller
        end,
        BindController = function(target, controller)
            if not target or not controller then
                return
            end

            target.OnLoad = function(_, frame)
                if controller.OnLoad then
                    controller:OnLoad(frame)
                end
            end

            target.Fetch = function()
                if controller.Fetch then
                    return controller:Fetch()
                end
            end

            target.Sort = function(_, key)
                if controller.Sort then
                    return controller:Sort(key)
                end
            end
        end,
    }

    addon.UI.Selection = {
        SetModifierPolicy = function() end,
        SetAnchor = function() end,
        GetCount = function()
            return 0
        end,
        GetSelected = function()
            return {}
        end,
        EnsureState = function() end,
        Toggle = function(_, id)
            return "toggle", (id and 1 or 0)
        end,
        GetAnchor = function()
            return nil
        end,
    }

    local Database = {}

    function Database.IsBossFightRecord(boss)
        return isBossFightRecord(boss)
    end

    Database._IsBossFightRecord = Database.IsBossFightRecord

    local function ensureNamespace(root, ...)
        assert(type(root) == "table", "ensureNamespace requires a root table")

        local target = root
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            assert(type(key) == "string" and key ~= "", "ensureNamespace requires non-empty string keys")

            local child = target[key]
            if type(child) ~= "table" then
                child = {}
                target[key] = child
            end
            target = child
        end

        return target
    end

    local feature = {
        L = L,
        Diag = Diag,
        Frames = addon.UI.Frames,
        Events = Events,
        C = C,
        coreState = addon.State,
        Database = Database,
        Options = (function()
            -- Stub matching the namespace registry API. Registered options live
            -- in `addon.options` (a flat table in tests) and in a key-to-namespace
            -- map for Options.Set.
            local namespaces = {}
            local keyToNs = {}
            local function getOrInitFlat()
                addon.options = addon.options or {}
                return addon.options
            end
            local function getOrInitNamespaceStore(name)
                _G.KRT_Options = type(_G.KRT_Options) == "table" and _G.KRT_Options or {}
                local store = _G.KRT_Options[name]
                if type(store) ~= "table" then
                    store = {}
                    _G.KRT_Options[name] = store
                end
                return store
            end
            local Opts = {}
            function Opts.IsDebugEnabled()
                return addon.State.debugEnabled == true
            end
            function Opts.SetDebugEnabled(enabled)
                addon.State.debugEnabled = enabled and true or false
            end
            function Opts.AddNamespace(name, defaults)
                local store = getOrInitFlat()
                local namespaceStore = getOrInitNamespaceStore(name)
                if namespaces[name] then
                    local ns = namespaces[name]
                    for k, v in pairs(defaults or {}) do
                        if ns._defaults[k] == nil then
                            ns._defaults[k] = v
                            if namespaceStore[k] ~= nil then
                                store[k] = namespaceStore[k]
                            elseif store[k] == nil then
                                store[k] = v
                                namespaceStore[k] = v
                            else
                                namespaceStore[k] = store[k]
                            end
                            keyToNs[k] = ns
                        end
                    end
                    return ns
                end
                local ns = { _name = name, _defaults = defaults or {} }
                for k, v in pairs(ns._defaults) do
                    if namespaceStore[k] ~= nil then
                        store[k] = namespaceStore[k]
                    elseif store[k] == nil then
                        store[k] = v
                        namespaceStore[k] = v
                    else
                        namespaceStore[k] = store[k]
                    end
                    keyToNs[k] = ns
                end
                function ns:Get(key)
                    local namespaceValue = getOrInitNamespaceStore(self._name)[key]
                    local v = namespaceValue ~= nil and namespaceValue or getOrInitFlat()[key]
                    if v == nil then
                        return self._defaults[key]
                    end
                    return v
                end
                function ns:Set(key, value)
                    getOrInitFlat()[key] = value
                    getOrInitNamespaceStore(self._name)[key] = value
                    return true
                end
                function ns:GetDefaults()
                    local out = {}
                    for k, v in pairs(self._defaults) do
                        out[k] = v
                    end
                    return out
                end
                function ns:ResetDefaults()
                    local store2 = getOrInitFlat()
                    local namespaceStore2 = getOrInitNamespaceStore(self._name)
                    for k, v in pairs(self._defaults) do
                        store2[k] = v
                        namespaceStore2[k] = v
                    end
                end
                function ns:All()
                    local out = {}
                    for k, v in pairs(self._defaults) do
                        out[k] = v
                    end
                    local store2 = getOrInitFlat()
                    for k, v in pairs(store2) do
                        if self._defaults[k] ~= nil then
                            out[k] = v
                        end
                    end
                    local namespaceStore2 = getOrInitNamespaceStore(self._name)
                    for k, v in pairs(namespaceStore2) do
                        if self._defaults[k] ~= nil then
                            out[k] = v
                        end
                    end
                    return out
                end
                function ns:Name()
                    return self._name
                end
                namespaces[name] = ns
                return ns
            end
            function Opts.Get(name)
                return namespaces[name]
            end
            function Opts.Set(key, value)
                local ns = keyToNs[key]
                if not ns then
                    return false
                end
                return ns:Set(key, value)
            end
            function Opts.EnsureLoaded() end
            function Opts.GetNamespaces()
                return namespaces
            end
            return Opts
        end)(),
        Bus = Bus,
        Strings = Strings,
        Colors = addon.Colors,
        Base64 = addon.Base64,
        Sort = Sort,
        Comms = addon.Comms,
        Item = addon.Item,
        Services = addon.Services,
        MakeModuleFrameGetter = function(module, defaultName)
            return function()
                return module.frame or _G[defaultName]
            end
        end,
        GetItemIndex = function()
            return 1
        end,
        tContains = function(tbl, value)
            if type(tbl) ~= "table" then
                return false
            end
            for i = 1, #tbl do
                if tbl[i] == value then
                    return true
                end
            end
            return false
        end,
        rollTypes = rollTypes,
        lootTypesColored = {},
        itemColors = {},
        RAID_TARGET_MARKERS = C.RAID_TARGET_MARKERS,
        ITEM_LINK_PATTERN = C.ITEM_LINK_PATTERN,
        lootState = {
            rollSession = nil,
            fromInventory = false,
            currentRollType = nil,
            currentRollItem = 0,
            pendingAwards = {},
        },
        raidState = {},
        Time = {
            GetCurrentTime = function()
                return 1000
            end,
        },
        OptionsTable = {},
    }

    Database.EnsureServiceNamespace = function(...)
        return ensureNamespace(addon.Services, ...)
    end

    local function hydrateFeatureShared()
        feature.L = addon.L or feature.L
        feature.Diag = addon.Diag or feature.Diag
        feature.UI = addon.UI or feature.UI
        feature.Events = addon.Events or feature.Events
        feature.C = addon.C or feature.C
        feature.coreState = addon.State or feature.coreState
        feature.Database = addon.Database or Database
        feature.DB = addon.DB or feature.DB
        feature.Options = addon.Options or feature.Options
        feature.Bus = addon.Bus or feature.Bus
        feature.Strings = addon.Strings or feature.Strings
        feature.Colors = addon.Colors or feature.Colors
        feature.Timer = addon.Timer or feature.Timer
        feature.Base64 = addon.Base64 or feature.Base64
        feature.Json = addon.Json or feature.Json
        feature.Sort = addon.Sort or feature.Sort
        feature.UI = addon.UI or feature.UI
        feature.Comms = addon.Comms or feature.Comms
        feature.Item = addon.Item or feature.Item
        feature.LootSourcesData = addon.LootSourcesData or feature.LootSourcesData
        feature.LootSources = addon.LootSources or feature.LootSources
        feature.IgnoredItems = addon.IgnoredItems or feature.IgnoredItems
        feature.IgnoredMobs = addon.IgnoredMobs or feature.IgnoredMobs
        feature.UI = addon.UI or feature.UI
        feature.Services = addon.Services or feature.Services
        feature.Controllers = addon.Controllers or feature.Controllers
        feature.Widgets = addon.Widgets or feature.Widgets
        feature.Time = addon.Time or feature.Time
        feature.Deformat = addon.Deformat or feature.Deformat
        feature.GetClassColor = addon.GetClassColor or feature.GetClassColor
        feature.GetCreatureId = addon.GetCreatureId or feature.GetCreatureId
        feature.BossIDs = addon.BossIDs or feature.BossIDs
        feature.GetGroupTypeAndCount = addon.GetGroupTypeAndCount or feature.GetGroupTypeAndCount
        feature.UnitIsGroupLeader = addon.UnitIsGroupLeader or feature.UnitIsGroupLeader
        feature.UnitIsGroupAssistant = addon.UnitIsGroupAssistant or feature.UnitIsGroupAssistant
        feature.EnsureServiceNamespace = Database.EnsureServiceNamespace
        return feature
    end

    addon.Options = feature.Options
    addon.Time = feature.Time
    addon.Bus = Bus
    addon.Database = Database
    addon.Database.GetFeatureShared = function()
        return hydrateFeatureShared()
    end
    Database.GetFeatureShared = addon.Database.GetFeatureShared
    Database.GetCurrentRaid = function()
        return addon.State.currentRaid
    end
    Database.GetLastBoss = function()
        return addon.State.lastBoss
    end
    Database.SetLastBoss = function(bossNid)
        addon.State.lastBoss = bossNid
        return addon.State.lastBoss
    end
    Database.GetPlayerName = function()
        return "Tester"
    end
    Database.GetRaidSchemaVersion = function()
        return 1
    end
    Database.GetRaidMigrations = function()
        return nil
    end
    Database.GetRaidQueries = function()
        return nil
    end
    Database.GetRaidQueriesOrNil = function()
        if type(Database.GetRaidQueries) ~= "function" then
            return nil
        end
        return Database.GetRaidQueries()
    end
    Database.GetRaidStoreOrNil = function()
        return nil
    end
    Database.RequireServiceMethod = function(serviceName, serviceTable, methodName)
        assert(type(serviceTable) == "table", "KRT missing service: " .. tostring(serviceName))
        local method = serviceTable[methodName]
        assert(type(method) == "function", "KRT missing service method: " .. tostring(serviceName) .. "." .. tostring(methodName))
        return method
    end

    if type(services.Loot.GetCurrentItemCount) ~= "function" then
        function services.Loot:GetCurrentItemCount()
            return tonumber(feature.itemInfo and feature.itemInfo.count) or tonumber(feature.lootState and feature.lootState.selectedItemCount) or 1
        end
    end

    if type(services.Loot.FindLootSlotIndex) ~= "function" then
        function services.Loot:FindLootSlotIndex(itemLink)
            local wantedKey = addon.Item.GetItemStringFromLink(itemLink) or itemLink
            local wantedId = addon.Item.GetItemIdFromLink(itemLink)
            local count = type(_G.GetNumLootItems) == "function" and (_G.GetNumLootItems() or 0) or 0
            for i = 1, count do
                local tempItemLink = type(_G.GetLootSlotLink) == "function" and _G.GetLootSlotLink(i) or nil
                if tempItemLink == itemLink then
                    return i
                end
                if wantedKey and tempItemLink then
                    local tempKey = addon.Item.GetItemStringFromLink(tempItemLink) or tempItemLink
                    if tempKey == wantedKey then
                        return i
                    end
                end
                if wantedId and tempItemLink then
                    local tempItemId = addon.Item.GetItemIdFromLink(tempItemLink)
                    if tempItemId and tempItemId == wantedId then
                        return i
                    end
                end
            end
            return nil
        end
    end

    if type(services.Loot.FindTradeableInventoryMatch) ~= "function" then
        function services.Loot:FindTradeableInventoryMatch(itemLink, itemId)
            if not itemLink and not itemId then
                return nil
            end

            local wantedKey = itemLink and (addon.Item.GetItemStringFromLink(itemLink) or itemLink) or nil
            local wantedId = tonumber(itemId) or (itemLink and addon.Item.GetItemIdFromLink(itemLink)) or nil
            local totalCount = 0
            local firstBag, firstSlot, firstSlotCount
            local hasMatch = false

            for bag = 0, 4 do
                local slots = type(_G.GetContainerNumSlots) == "function" and (_G.GetContainerNumSlots(bag) or 0) or 0
                for slot = 1, slots do
                    local link = type(_G.GetContainerItemLink) == "function" and _G.GetContainerItemLink(bag, slot) or nil
                    if link then
                        local key = addon.Item.GetItemStringFromLink(link) or link
                        local linkId = addon.Item.GetItemIdFromLink(link)
                        local matches = (wantedKey and key == wantedKey) or (wantedId and linkId == wantedId)
                        if matches then
                            hasMatch = true
                            local _, count = type(_G.GetContainerItemInfo) == "function" and _G.GetContainerItemInfo(bag, slot) or nil, 0
                            if type(_G.GetContainerItemInfo) == "function" then
                                _, count = _G.GetContainerItemInfo(bag, slot)
                            end
                            local slotCount = tonumber(count) or 1
                            totalCount = totalCount + slotCount
                            if not firstBag then
                                firstBag = bag
                                firstSlot = slot
                                firstSlotCount = slotCount
                            end
                        end
                    end
                end
            end

            return totalCount, firstBag, firstSlot, firstSlotCount, hasMatch
        end
    end

    if type(services.Loot.FindTradeableInventoryItem) ~= "function" then
        function services.Loot:FindTradeableInventoryItem(itemLink, cachedBag, cachedSlot, selectedItemCount)
            local totalCount, bag, slot, slotCount
            local usedFastPath = false
            local wantedKey = addon.Item.GetItemStringFromLink(itemLink) or itemLink
            local wantedId = addon.Item.GetItemIdFromLink(itemLink)

            cachedBag = tonumber(cachedBag)
            cachedSlot = tonumber(cachedSlot)

            if cachedBag and cachedSlot then
                local cachedLink = type(_G.GetContainerItemLink) == "function" and _G.GetContainerItemLink(cachedBag, cachedSlot) or nil
                if cachedLink then
                    local cachedKey = addon.Item.GetItemStringFromLink(cachedLink) or cachedLink
                    local cachedId = addon.Item.GetItemIdFromLink(cachedLink)
                    local sameItem = (wantedKey and cachedKey == wantedKey) or (wantedId and cachedId == wantedId)
                    if sameItem then
                        local _, count = type(_G.GetContainerItemInfo) == "function" and _G.GetContainerItemInfo(cachedBag, cachedSlot) or nil, 0
                        if type(_G.GetContainerItemInfo) == "function" then
                            _, count = _G.GetContainerItemInfo(cachedBag, cachedSlot)
                        end
                        bag = cachedBag
                        slot = cachedSlot
                        slotCount = tonumber(count) or 1
                        usedFastPath = true
                    end
                end
            end

            if not (bag and slot) then
                totalCount, bag, slot, slotCount = self:FindTradeableInventoryMatch(itemLink, wantedId)
            elseif usedFastPath then
                if (tonumber(selectedItemCount) or 1) > 1 then
                    totalCount = self:FindTradeableInventoryMatch(itemLink, wantedId)
                else
                    totalCount = tonumber(slotCount) or 1
                end
            end

            if not (bag and slot) then
                return nil
            end

            return {
                bag = bag,
                slot = slot,
                slotCount = tonumber(slotCount) or 1,
                totalCount = tonumber(totalCount) or tonumber(slotCount) or 1,
            }
        end
    end

    if type(services.Rolls.GetRollSessionItemKey) ~= "function" then
        function services.Rolls:GetRollSessionItemKey(itemLink)
            if not itemLink then
                return nil
            end
            return addon.Item.GetItemStringFromLink(itemLink) or itemLink
        end
    end

    if type(services.Rolls.SetExpectedWinners) ~= "function" then
        function services.Rolls:SetExpectedWinners(count)
            local session = feature.lootState.rollSession
            if not session then
                return nil
            end
            count = tonumber(count) or tonumber(feature.lootState.selectedItemCount) or 1
            if count < 1 then
                count = 1
            end
            session.expectedWinners = count
            return count
        end
    end

    if type(services.Rolls.EnsureRollSession) ~= "function" then
        function services.Rolls:EnsureRollSession(itemLink, rollType, source)
            local session = feature.lootState.rollSession
            if not session then
                local nextId = tonumber(feature.lootState.nextRollSessionId) or 1
                if nextId < 1 then
                    nextId = 1
                end
                feature.lootState.nextRollSessionId = nextId + 1
                session = {
                    id = "RS:" .. tostring(nextId),
                    itemKey = self:GetRollSessionItemKey(itemLink),
                    itemId = addon.Item.GetItemIdFromLink(itemLink),
                    itemLink = itemLink,
                    rollType = tonumber(rollType) or tonumber(feature.lootState.currentRollType) or rollTypes.FREE,
                    lootNid = tonumber(feature.lootState.currentRollItem) or 0,
                    startedAt = (_G.GetTime and _G.GetTime()) or 0,
                    endsAt = nil,
                    source = source or (feature.lootState.fromInventory and "inventory" or "lootWindow"),
                    expectedWinners = tonumber(feature.lootState.selectedItemCount) or 1,
                    active = true,
                }
                feature.lootState.rollSession = session
                feature.lootState.rollStarted = true
            else
                if itemLink then
                    session.itemLink = itemLink
                    session.itemKey = self:GetRollSessionItemKey(itemLink)
                    session.itemId = addon.Item.GetItemIdFromLink(itemLink)
                end
                if rollType ~= nil then
                    session.rollType = tonumber(rollType) or session.rollType
                end
                session.source = source or session.source
                session.active = true
                session.endsAt = nil
            end
            self:SetExpectedWinners(feature.lootState.selectedItemCount)
            self:SyncSessionState(session)
            return session
        end
    end

    if type(services.Rolls.EnsureLootRollSession) ~= "function" then
        function services.Rolls:EnsureLootRollSession(itemLink, rollType, source, _opts)
            return self:EnsureRollSession(itemLink, rollType, source)
        end
    end

    local function parseItemId(value)
        if type(value) == "number" then
            return value
        end
        if type(value) ~= "string" then
            return nil
        end
        return tonumber(value:match("item:(%-?%d+)"))
    end

    local function registerItem(itemId, name, rarity, icon)
        local itemName = name or ("Item" .. tostring(itemId))
        local itemLink = ("|cff0070dd|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r"):format(itemId, itemName)
        itemRegistry[itemId] = {
            name = itemName,
            link = itemLink,
            rarity = rarity or 4,
            icon = icon or ("Icon" .. tostring(itemId)),
        }
        return itemLink
    end

    _G.UIParent = makeFrame(true, "UIParent")
    _G.ChatFontNormal = {}
    _G.StaticPopupDialogs = {}
    _G.RAID_CLASS_COLORS = {}
    _G.UNKNOWNOBJECT = "UNKNOWNOBJECT"
    _G.UNKNOWNBEING = "UNKNOWNBEING"
    _G.LOOT_ITEM_MULTIPLE = "LOOT_ITEM_MULTIPLE"
    _G.LOOT_ITEM = "LOOT_ITEM"
    _G.LOOT_ITEM_SELF_MULTIPLE = "LOOT_ITEM_SELF_MULTIPLE"
    _G.LOOT_ITEM_SELF = "LOOT_ITEM_SELF"
    _G.LOOT_ROLL_YOU_WON = "You won: %s"
    _G.LOOT_ROLL_WON = "%s won: %s"
    _G.LOOT_ROLL_NEED = "%s has selected Need for: %s"
    _G.LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
    _G.LOOT_ROLL_GREED = "%s has selected Greed for: %s"
    _G.LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s"
    _G.LOOT_ROLL_DISENCHANT = "%s has selected Disenchant for: %s"
    _G.LOOT_ROLL_DISENCHANT_SELF = "You have selected Disenchant for: %s"
    _G.LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
    _G.LOOT_ROLL_ROLLED_NEED_SELF = _G.LOOT_ROLL_ROLLED_NEED
    _G.LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s"
    _G.LOOT_ROLL_ROLLED_GREED_SELF = _G.LOOT_ROLL_ROLLED_GREED
    _G.LOOT_ROLL_ROLLED_DE = "Disenchant Roll - %d for %s by %s"
    _G.LOOT_ROLL_ROLLED_DE_SELF = _G.LOOT_ROLL_ROLLED_DE
    _G.LOOT_ROLL_WON_NO_SPAM_NEED = "%1$s won: %3$s |cff818181(Need - %2$d)|r"
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED = "You won: %2$s |cff818181(Need - %1$d)|r"
    _G.LOOT_ROLL_WON_NO_SPAM_GREED = "%1$s won: %3$s |cff818181(Greed - %2$d)|r"
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED = "You won: %2$s |cff818181(Greed - %1$d)|r"
    _G.LOOT_ROLL_WON_NO_SPAM_DE = "%1$s won: %3$s |cff818181(Disenchant - %2$d)|r"
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_DE = "You won: %2$s |cff818181(Disenchant - %1$d)|r"
    _G.LOOT_ROLL_WON_NO_SPAM_DISENCHANT = _G.LOOT_ROLL_WON_NO_SPAM_DE
    _G.LOOT_ROLL_YOU_WON_NO_SPAM_DISENCHANT = _G.LOOT_ROLL_YOU_WON_NO_SPAM_DE
    _G.TRADE = "Trade"
    _G.strmatch = string.match
    _G.RAID_TARGET_MARKERS = {
        "{rt1}",
        "{rt2}",
        "{rt3}",
        "{rt4}",
        "{rt5}",
        "{rt6}",
        "{rt7}",
        "{rt8}",
    }
    _G.IsControlKeyDown = function()
        return false
    end
    _G.IsShiftKeyDown = function()
        return false
    end
    _G.GetTime = function()
        return 1000
    end
    _G.SetRaidTarget = function() end
    _G.CheckInteractDistance = function()
        return 1
    end
    _G.GetContainerNumSlots = function()
        return 0
    end
    _G.GetContainerItemLink = function()
        return nil
    end
    _G.GetContainerItemInfo = function()
        return nil, 0
    end
    _G.ClearCursor = function() end
    _G.PickupContainerItem = function() end
    _G.CursorHasItem = function()
        return false
    end
    _G.InitiateTrade = function() end

    _G.GameTooltip = {
        SetOwner = function() end,
        SetHyperlink = function() end,
        Hide = function() end,
    }

    _G.CreateFrame = function(_, name)
        local frame = makeFrame(true, name)
        if name then
            _G[name] = frame
        end
        return frame
    end

    _G.PanelTemplates_SetTab = function(frame, tabId)
        if frame then
            frame._tabId = tabId
        end
    end

    _G.PanelTemplates_SetNumTabs = function(frame, count)
        if frame then
            frame._tabCount = count
        end
    end

    _G.StaticPopup_Show = function()
        return nil
    end

    _G.StaticPopup_Hide = function() end

    _G.CloseDropDownMenus = function() end

    _G.UIDropDownMenu_CreateInfo = function()
        return {}
    end

    _G.UIDropDownMenu_AddButton = function() end

    _G.UIDropDownMenu_Initialize = function(frame, initFunc)
        if frame then
            frame._initialize = initFunc
        end
    end

    _G.UIDropDownMenu_SetText = function(frame, value)
        if frame then
            frame._dropdownText = value
        end
    end

    _G.UIDropDownMenu_SetSelectedValue = function(frame, value)
        if frame then
            frame._selectedValue = value
        end
    end

    _G.EasyMenu = function() end

    _G.GetLootThreshold = function()
        return 0
    end

    _G.IsInInstance = function()
        return false, "none"
    end

    _G.GetNumRaidMembers = function()
        return 0
    end

    _G.GetNumPartyMembers = function()
        return 0
    end

    _G.SendAddonMessage = function() end

    _G.RegisterAddonMessagePrefix = function()
        return true
    end

    _G.UnitName = function()
        return "Tester"
    end

    _G.GetItemInfo = function(value)
        local itemId = parseItemId(value)
        local item = itemId and itemRegistry[itemId] or nil
        if not item then
            return nil
        end
        return item.name, item.link, item.rarity, nil, nil, nil, nil, nil, nil, item.icon
    end

    _G.GetItemIcon = function(value)
        local itemId = parseItemId(value)
        local item = itemId and itemRegistry[itemId] or nil
        return item and item.icon or nil
    end

    _G.GetLootRollItemLink = function()
        return nil
    end

    _G.time = _G.time or os.time
    _G.date = _G.date or os.date

    addon.Deformat = function()
        return nil
    end

    local harness = {
        addon = addon,
        Database = Database,
        feature = feature,
        Bus = Bus,
        logs = logs,
        C = C,
        rollTypes = rollTypes,
        makeFrame = makeFrame,
        registerItem = registerItem,
        load = function(_, path)
            ensureCanonicalChatService()
            ensureCanonicalRaidCapabilityService()

            local lootServiceFiles = {
                "!KRT/Services/Loot/Context.lua",
                "!KRT/Services/Loot/State.lua",
                "!KRT/Services/Loot/Snapshots.lua",
                "!KRT/Services/Loot/PendingAwards.lua",
                "!KRT/Services/Loot/PassiveGroupLoot.lua",
                "!KRT/Services/Loot/Tracking.lua",
                "!KRT/Services/Loot/Workflow.lua",
                "!KRT/Services/Loot/Receipts.lua",
                "!KRT/Services/Loot/Records.lua",
                "!KRT/Services/Loot/Reconcile.lua",
                "!KRT/Services/Loot/Rules.lua",
                "!KRT/Services/Loot/DistributionSession.lua",
                "!KRT/Services/Loot/Service.lua",
            }
            local lootSourceFiles = {
                "!KRT/Modules/Dataset/IgnoredMobs.lua",
                "!KRT/Modules/LootSourceCandidates.lua",
                "!KRT/Modules/Dataset/LootSourcesData.lua",
                "!KRT/Modules/LootSources.lua",
            }
            local raidServiceFiles = {
                "!KRT/Services/Raid/State.lua",
                "!KRT/Services/Raid/Capabilities.lua",
                "!KRT/Services/Raid/Counts.lua",
                "!KRT/Services/Raid/Roster.lua",
                "!KRT/Services/Raid/Attendance.lua",
                "!KRT/Services/Raid/LootRecords.lua",
                "!KRT/Services/Raid/Session.lua",
                "!KRT/Services/Raid/LootMethod.lua",
            }

            local function loadFiles(files)
                for i = 1, #files do
                    local chunk, err = loadfile(files[i])
                    if not chunk then
                        error(err, 0)
                    end
                    chunk("!KRT", addon)
                end
            end

            local function ensureRaidQueries()
                if not addon.LootSourceCandidates then
                    loadFiles({ "!KRT/Modules/LootSourceCandidates.lua" })
                end
                if not (addon.DB and addon.DB.RaidQueries) then
                    loadFiles({ "!KRT/Database/DBRaidQueries.lua" })
                end
                Database.GetRaidQueries = function()
                    return addon.DB and addon.DB.RaidQueries or nil
                end
            end

            if path == "!KRT/Modules/LootSources.lua" then
                loadFiles(lootSourceFiles)
                feature.LootSources = addon.LootSources
                return addon.LootSources
            end

            if path == "!KRT/Database/DBRaidQueries.lua" then
                ensureRaidQueries()
                return addon.DB and addon.DB.RaidQueries or nil
            end

            if path == "!KRT/Services/Loot.lua" then
                loadFiles(lootSourceFiles)
                feature.LootSources = addon.LootSources
                ensureRaidQueries()
                loadFiles(lootServiceFiles)
                return addon.Services.Loot
            end

            if path == "!KRT/Services/Raid.lua" then
                loadFiles(lootSourceFiles)
                feature.LootSources = addon.LootSources
                ensureRaidQueries()
                loadFiles(lootServiceFiles)
                loadFiles(raidServiceFiles)
                local raid = addon.Services.Raid
                local loot = addon.Services.Loot
                if raid and loot then
                    -- Test harness compatibility: production moved passive/trade loot ingestion
                    -- to Services.Loot; keep existing Raid call sites in tests functional.
                    raid.AddLoot = raid.AddLoot or function(_, ...)
                        return loot:AddLoot(...)
                    end
                    raid.AddPassiveLootRoll = raid.AddPassiveLootRoll or function(_, ...)
                        return loot:AddPassiveLootRoll(...)
                    end
                    raid.AddGroupLootMessage = raid.AddGroupLootMessage or function(_, ...)
                        return loot:AddGroupLootMessage(...)
                    end
                    raid.LogTradeOnlyLoot = raid.LogTradeOnlyLoot or function(_, ...)
                        return loot:LogTradeOnlyLoot(...)
                    end
                end
                return addon.Services.Raid
            end

            if path == "!KRT/Services/Rolls/Service.lua" then
                loadFiles({
                    "!KRT/Services/Rolls/Countdown.lua",
                    "!KRT/Services/Rolls/Sessions.lua",
                    "!KRT/Services/Rolls/History.lua",
                    "!KRT/Services/Rolls/Responses.lua",
                    "!KRT/Services/Rolls/Strategies.lua",
                    "!KRT/Services/Rolls/Resolution.lua",
                    "!KRT/Services/Rolls/Display.lua",
                })
            end

            if path == "!KRT/Services/Reserves.lua" then
                loadFiles({
                    "!KRT/Services/Reserves/Import.lua",
                    "!KRT/Services/Reserves/Aliases.lua",
                    "!KRT/Services/Reserves/Display.lua",
                    "!KRT/Services/Reserves/Sync.lua",
                })
            end

            if path == "!KRT/Controllers/Logger.lua" or path == "!KRT/Database/DBRaidValidator.lua" then
                loadFiles({ "!KRT/Modules/Dataset/IgnoredMobs.lua" })
            end

            if path == "!KRT/Database/DBSyncer.lua" or path == "!KRT/Services/Logger/Store.lua" or path == "!KRT/Services/Logger/Actions.lua" then
                ensureRaidQueries()
            end

            local chunk, err = loadfile(path)
            if not chunk then
                error(err, 0)
            end
            return chunk("!KRT", addon)
        end,
        flushTimers = function()
            addon._flushTimers()
        end,
        timerCount = function()
            return addon._timerCount()
        end,
        setRaidRoleState = function(_, state)
            raidRoleOverride = type(state) == "table" and copyTable(state) or nil
        end,
        setRaidCapabilityState = function(_, capability, allowed, reason)
            if type(capability) ~= "string" or capability == "" then
                return
            end
            if type(allowed) == "table" then
                raidCapabilityOverrides[capability] = copyTable(allowed)
                return
            end
            if allowed == nil then
                raidCapabilityOverrides[capability] = nil
                return
            end
            raidCapabilityOverrides[capability] = {
                allowed = allowed == true,
                reason = reason,
            }
        end,
    }

    function harness:installRaidStore(seedRaids)
        _G.KRT_Raids = seedRaids or {}
        self:load("!KRT/Database/DBRaidStore.lua")
        local store = self.addon.DB.RaidStore
        store:NormalizeAllRaids()
        self.store = store
        self.Database.GetRaidStoreOrNil = function()
            return store
        end
        self.Database.EnsureRaidSchema = function(raid)
            return store:NormalizeRaidRecord(raid)
        end
        self.Database.StripRuntimeRaidCaches = function(raid)
            return store:StripRuntime(raid)
        end
        self.Database.EnsureRaidById = function(raidId)
            if not raidId then
                return nil
            end
            local raid = store:GetRaidByIndex(raidId)
            return raid and store:NormalizeRaidRecord(raid) or nil
        end
        self.Database.EnsureRaidByNid = function(raidNid)
            if not raidNid then
                return nil
            end
            local raid = store:GetRaidByNid(raidNid)
            return raid and store:NormalizeRaidRecord(raid) or nil
        end
        return store
    end

    return harness
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected truthy value", 0)
    end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "unexpected value") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual), 0)
    end
end

local function assertContains(entries, needle, message)
    for i = 1, #entries do
        if string.find(entries[i], needle, 1, true) then
            return
        end
    end
    error(message or ("expected log entry containing '" .. tostring(needle) .. "'"), 0)
end

local function assertTextContains(text, needle, message)
    if not string.find(tostring(text or ""), tostring(needle or ""), 1, true) then
        error(message or ("expected text containing '" .. tostring(needle) .. "'"), 0)
    end
end

local function assertTextNotContains(text, needle, message)
    if string.find(tostring(text or ""), tostring(needle or ""), 1, true) then
        error(message or ("expected text not to contain '" .. tostring(needle) .. "'"), 0)
    end
end

local function readText(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function countTextPattern(text, pattern)
    local count = 0
    for _ in tostring(text or ""):gmatch(pattern) do
        count = count + 1
    end
    return count
end

local function setHarnessOption(h, namespace, key, value, defaults)
    local cfg = h.addon.Options.AddNamespace(namespace, defaults or {})
    cfg:Set(key, value)
    return cfg
end

local function getHarnessOption(h, namespace, key)
    local cfg = h.addon.Options.Get(namespace)
    return cfg and cfg:Get(key) or nil
end

local function setupLoggerExportHarness(seedRaids)
    local h = newHarness()
    h.feature.Sort.GetLootSortName = function(itemName, itemLink, itemId)
        return tostring(itemName or itemLink or itemId or "")
    end
    h:installRaidStore(seedRaids)
    h:load("!KRT/Database/DBRaidQueries.lua")
    h.Database.GetRaidQueries = function()
        return h.addon.DB.RaidQueries
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Export.lua")
    return h, h.Database.EnsureRaidById(1), h.addon.Services.Logger.Export
end

local function loadMasterController(h)
    h:load("!KRT/Services/Master/SoftRes.lua")
    h:load("!KRT/Services/Master/SessionWinners.lua")
    h:load("!KRT/Services/Master/FlowState.lua")
    h:load("!KRT/Services/Master/ButtonState.lua")
    h:load("!KRT/Services/Master/RollRows.lua")
    h:load("!KRT/Services/Master/AssignmentHelpers.lua")
    h:load("!KRT/Services/Master/AssignmentCandidates.lua")
    h:load("!KRT/Services/Master/AssignmentTargets.lua")
    h:load("!KRT/Services/Master/DebugRaidGrid.lua")
    h:load("!KRT/Services/Master/AwardMessages.lua")
    h:load("!KRT/Services/Master/LootSpam.lua")
    h:load("!KRT/Services/Master/AwardCounter.lua")
    h:load("!KRT/Services/Master/RollAnnouncements.lua")
    h:load("!KRT/Services/Master/Service.lua")
    h:load("!KRT/Widgets/LootHints.lua")
    h:load("!KRT/Controllers/Master.lua")
end

local function seedRaidGridButtonChildren(h, buttonName)
    local suffixes = {
        "Bg",
        "TopLine",
        "BottomLine",
        "Highlight",
        "Text",
        "SpecIcon",
    }
    for i = 1, #suffixes do
        local childName = buttonName .. suffixes[i]
        if not _G[childName] then
            _G[childName] = h.makeFrame(true, childName)
        end
    end
end

local function loadRaidGridWidget(h)
    if not _G.KRTRaidGridFrame then
        local frame = h.makeFrame(true, "KRTRaidGridFrame")
        _G.KRTRaidGridFrame = frame
        local childNames = {
            "KRTRaidGridFrameIcon",
            "KRTRaidGridFrameTitle",
            "KRTRaidGridFrameContextTitle",
            "KRTRaidGridFrameCount",
            "KRTRaidGridFrameDivider",
            "KRTRaidGridFrameEmpty",
            "KRTRaidGridFrameCloseButton",
        }
        for i = 1, #childNames do
            local name = childNames[i]
            _G[name] = h.makeFrame(true, name)
        end
    end
    if _G.__KRT_RaidGrid_CreateFrameWrapper ~= _G.CreateFrame then
        local baseCreateFrame = _G.CreateFrame
        local raidGridCreateFrame = function(frameType, name, parent, template, ...)
            local frame = baseCreateFrame(frameType, name, parent, template, ...)
            if name and template == "KRTRaidGridButtonTemplate" then
                seedRaidGridButtonChildren(h, name)
            end
            return frame
        end
        _G.CreateFrame = raidGridCreateFrame
        _G.__KRT_RaidGrid_CreateFrameBase = baseCreateFrame
        _G.__KRT_RaidGrid_CreateFrameWrapper = raidGridCreateFrame
    end
    h:load("!KRT/Widgets/RaidGrid.lua")
end

local function loadMasterFrameForTest(Master, frame)
    return Master._Private.LoadFrame(frame)
end

local function refreshMasterFrameForTest(Master)
    return Master._Private.RefreshFrame()
end

local function installMasterFrameParts(h, frame)
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")
end

local function setupInventoryTradeHarness(order, rollsByName)
    local h = newHarness()
    local link = h.registerItem(9304, "Queueblade")
    local bagItems = {
        [0] = {
            [1] = { link = link, count = 1 },
            [2] = { link = link, count = 1 },
        },
    }
    local initiatedTrades = {}
    local addCounts = {}
    local loggerRequests = {}
    local clearLootCount = 0
    local clearIconsCount = 0
    local cursorHasItem = false

    _G.GetContainerNumSlots = function(bag)
        local slots = bagItems[bag]
        return slots and 2 or 0
    end
    _G.GetContainerItemLink = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return item and item.link or nil
    end
    _G.GetContainerItemInfo = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return nil, item and item.count or 0
    end
    _G.ClearCursor = function()
        cursorHasItem = false
    end
    _G.PickupContainerItem = function(bag, slot)
        cursorHasItem = (bagItems[bag] and bagItems[bag][slot]) ~= nil
    end
    _G.CursorHasItem = function()
        return cursorHasItem
    end
    _G.InitiateTrade = function(playerName)
        initiatedTrades[#initiatedTrades + 1] = playerName
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI

    local function getSelectedWinners()
        local selected = {}
        for i = 1, #order do
            local name = order[i]
            if h.addon.UI.Selection.IsSelected("MLRollWinners", name) then
                selected[#selected + 1] = {
                    name = name,
                    roll = rollsByName[name] or 0,
                }
            end
        end
        return selected
    end

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
        GetCurrentItemCount = function()
            return tonumber(h.feature.itemInfo and h.feature.itemInfo.count) or tonumber(h.feature.lootState and h.feature.lootState.selectedItemCount) or 1
        end,
        ClearLoot = function()
            clearLootCount = clearLootCount + 1
        end,
        ItemIsSoulbound = function()
            return false
        end,
        FindTradeableInventoryItem = function(_, itemLinkArg)
            if itemLinkArg ~= link then
                return nil
            end

            local firstBag, firstSlot, firstSlotCount
            local totalCount = 0

            for bag = 0, 4 do
                local slots = bagItems[bag]
                if slots then
                    for slot = 1, 4 do
                        local item = slots[slot]
                        if item and item.link == link then
                            local count = tonumber(item.count) or 1
                            totalCount = totalCount + count
                            if not firstBag then
                                firstBag = bag
                                firstSlot = slot
                                firstSlotCount = count
                            end
                        end
                    end
                end
            end

            if not firstBag then
                return nil
            end

            return {
                bag = firstBag,
                slot = firstSlot,
                slotCount = firstSlotCount,
                totalCount = totalCount,
            }
        end,
        ResolveTradeAwardedCount = function()
            local before = tonumber(h.feature.itemInfo.tradeStartCount)
            local bag = tonumber(h.feature.itemInfo.tradeStartBag) or tonumber(h.feature.itemInfo.bagID)
            local slot = tonumber(h.feature.itemInfo.tradeStartSlot) or tonumber(h.feature.itemInfo.slotID)
            if not (before and bag and slot) then
                return 1
            end

            local item = bagItems[bag] and bagItems[bag][slot] or nil
            local after = item and (tonumber(item.count) or 1) or 0
            local delta = before - after
            if delta > 0 then
                return delta
            end
            return 1
        end,
        ResolveInventoryAwardedCount = function()
            local awardedCount = tonumber(h.feature.lootState.selectedItemCount) or 1
            if awardedCount < 1 then
                awardedCount = 1
            end
            if h.feature.lootState.fromInventory and awardedCount > 1 then
                awardedCount = 1
            end
            return awardedCount
        end,
        BuildTradeNotificationPlan = function(_, args)
            local keep = not (args and args.isAwardRoll)
            local markerPlan
            local output
            if keep then
                output = "keep-output"
            elseif (tonumber(args and args.selectedItemCount) or 1) > 1 then
                output = "multi-output"
                markerPlan = {
                    clearRaidIcons = true,
                    raidTargets = {},
                }
            else
                output = "award-output"
            end
            return {
                keep = keep,
                output = output,
                whisper = keep and "keep-whisper" or nil,
                markerPlan = markerPlan,
            }
        end,
        BuildAwardTargetPlan = function(_, args)
            local target = tonumber(args and args.selectedItemCount) or 1
            if target < 1 then
                target = 1
            end
            local available = tonumber(args and args.availableItemCount) or 1
            if available < 1 then
                available = 1
            end
            if target > available then
                target = available
            end
            local rollsCount = tonumber(args and args.rollsCount)
            if rollsCount and target > rollsCount then
                target = rollsCount
            end
            return {
                target = target,
                available = available,
            }
        end,
        ValidateInventoryTradeSelection = function(_, args)
            local target = tonumber(args and args.target) or 1
            local selectedCount = tonumber(args and args.selectedCount) or 0
            local pickedCount = tonumber(args and args.pickedCount) or 0
            if selectedCount <= 0 then
                return {
                    ok = false,
                    errType = "empty_selection",
                }
            end
            if pickedCount < target then
                return {
                    ok = false,
                    errType = "not_enough_selection",
                    wantedCount = target,
                    pickedCount = pickedCount,
                }
            end
            return { ok = true }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function()
            clearIconsCount = clearIconsCount + 1
        end,
        AddPlayerCount = function(_, playerName, count)
            addCounts[#addCounts + 1] = {
                name = playerName,
                count = count,
            }
        end,
        AddPlayerCountForRollType = function(_, playerName, rollType, count)
            addCounts[#addCounts + 1] = {
                name = playerName,
                rollType = rollType,
                count = count,
            }
        end,
        GetUnitID = function(_, playerName)
            if not playerName or playerName == "" then
                return "none"
            end
            return "target"
        end,
        GetHeldLootNid = function()
            return 701
        end,
    }
    h.addon.Services.Rolls = {
        GetRollSession = function()
            return h.feature.lootState.rollSession
        end,
        SyncSessionState = function(_, session)
            h.feature.lootState.rollSession = session
        end,
        GetHighestRoll = function(_, winnerName)
            local winner = winnerName or h.feature.lootState.winner
            return rollsByName[winner] or 0
        end,
        GetDisplayModel = function()
            local rows = {}
            local selected = getSelectedWinners()
            for i = 1, #order do
                local name = order[i]
                rows[i] = {
                    id = i,
                    name = name,
                    roll = rollsByName[name] or 0,
                    status = "ROLL",
                    isEligible = true,
                    counterText = "",
                    infoText = "",
                    class = "MAGE",
                    isReserved = false,
                    hasExplicitResponse = false,
                }
            end
            return {
                rows = rows,
                selectionAllowed = true,
                requiredWinnerCount = tonumber(h.feature.lootState.selectedItemCount) or 1,
                resolution = {
                    autoWinners = selected,
                    tiedNames = {},
                    requiresManualResolution = false,
                    topRollName = order[1],
                },
            }
        end,
        GetSelectedWinnersOrdered = function()
            return getSelectedWinners()
        end,
        GetRolls = function()
            return getSelectedWinners()
        end,
        ClearRolls = function() end,
        SetRollRecordingEnabled = function() end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h.feature.RAID_TARGET_MARKERS = h.C.RAID_TARGET_MARKERS

    h.Bus.RegisterCallback(h.addon.Events.Internal.LoggerLootLogRequest, function(_, request)
        loggerRequests[#loggerRequests + 1] = {
            lootNid = request.lootNid,
            looter = request.looter,
            rollType = request.rollType,
            rollValue = request.rollValue,
            source = request.source,
        }
        request.ok = true
    end)

    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function() end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = #order
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true
    h.feature.lootState.winner = order[1]

    h.addon.UI.Selection.EnsureState("MLRollWinners")
    for i = 1, #order do
        h.addon.UI.Selection.Toggle("MLRollWinners", order[i], true)
    end

    return {
        h = h,
        link = link,
        Master = Master,
        bagItems = bagItems,
        initiatedTrades = initiatedTrades,
        addCounts = addCounts,
        loggerRequests = loggerRequests,
        getClearLootCount = function()
            return clearLootCount
        end,
        getClearIconsCount = function()
            return clearIconsCount
        end,
    }
end

local function makeMasterRollRow(name, roll, status, isEligible, selectionAllowed)
    local rowStatus = status or "ROLL"
    local rowEligible = (isEligible ~= false)
    if selectionAllowed == nil then
        selectionAllowed = rowStatus == "ROLL" and rowEligible
    end
    return {
        name = name,
        roll = roll,
        status = rowStatus,
        isEligible = rowEligible,
        counterText = "",
        infoText = "",
        class = "MAGE",
        isReserved = false,
        selectionAllowed = selectionAllowed,
        hasExplicitResponse = (rowStatus == "PASS" or rowStatus == "CANCELLED"),
    }
end

local function setupMasterAwardHarness(cfg)
    local h = newHarness()
    local link = h.registerItem(cfg.itemId or 9313, cfg.itemName or "AwardHarnessBlade")
    local lootSlotLink = cfg.lootSlotLink or link
    local selectedLootQuality = tonumber(cfg.selectedLootQuality) or 3
    local selectedLootSlot = tonumber(cfg.selectedLootSlot) or 1
    local currentModel = cfg.model or {}
    local candidates = cfg.candidates or { "Alice", "Bob", "Cara" }
    local raidRecord = cfg.raidRecord or {
        holder = cfg.holder,
        banker = cfg.banker,
        disenchanter = cfg.disenchanter,
    }
    local candidateCache = {
        itemLink = nil,
        indexByName = {},
    }
    local queuedAwards = {}
    local givenLoot = {}
    local addCounts = {}
    local validationCalls = {}
    local refreshCount = 0

    local function rebuildCandidateCache(itemLinkArg)
        candidateCache.itemLink = itemLinkArg
        table.wipe(candidateCache.indexByName)
        for i = 1, #candidates do
            local candidate = candidates[i]
            if candidate and candidate ~= "" then
                candidateCache.indexByName[candidate] = i
            end
        end
        return candidateCache
    end

    _G.GetNumLootItems = function()
        return 1
    end
    _G.LootFrame = h.makeFrame(true, "LootFrame")
    _G.LootFrame.selectedSlot = selectedLootSlot
    _G.LootFrame.selectedQuality = selectedLootQuality
    _G.LootButton1 = h.makeFrame(true, "LootButton1")
    _G.LootFrame.selectedLootButton = _G.LootButton1
    _G.GetLootSlotLink = function(index)
        if index == selectedLootSlot then
            return lootSlotLink
        end
        return nil
    end
    _G.GetLootSlotInfo = function(index)
        if index == selectedLootSlot then
            return "test-icon", cfg.itemName or "AwardHarnessBlade", tonumber(cfg.lootQuantity) or 1, selectedLootQuality
        end
        return nil
    end
    _G.GetRaidRosterVersion = function()
        return 1
    end
    _G.GetMasterLootCandidate = function(index)
        return candidates[index]
    end
    _G.GiveMasterLoot = function(itemIndex, candidateIndex)
        givenLoot[#givenLoot + 1] = {
            itemIndex = itemIndex,
            candidateIndex = candidateIndex,
        }
    end

    h.addon.GetNumGroupMembers = function()
        return #candidates
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
        GetCurrentItemCount = function()
            return tonumber(h.feature.itemInfo and h.feature.itemInfo.count) or tonumber(h.feature.lootState and h.feature.lootState.selectedItemCount) or 1
        end,
        FindLootSlotIndex = function(_, itemLinkArg)
            local wantedKey = h.addon.Item.GetItemStringFromLink(itemLinkArg) or itemLinkArg
            local wantedId = h.addon.Item.GetItemIdFromLink(itemLinkArg)
            local slotKey = h.addon.Item.GetItemStringFromLink(link) or link
            local slotId = h.addon.Item.GetItemIdFromLink(link)
            if itemLinkArg == link or (wantedKey and slotKey == wantedKey) or (wantedId and slotId and slotId == wantedId) then
                return 1
            end
            return nil
        end,
        FetchLoot = function() end,
        AddPendingAward = function(_, itemLinkArg, playerName, rollType, rollValue, sessionId, expiresAt, options)
            queuedAwards[#queuedAwards + 1] = {
                itemLink = itemLinkArg,
                playerName = playerName,
                rollType = rollType,
                rollValue = rollValue,
                sessionId = sessionId,
                expiresAt = expiresAt,
                options = options,
            }
        end,
        BuildAwardTargetPlan = function(_, args)
            local target = tonumber(args and args.selectedItemCount) or 1
            if target < 1 then
                target = 1
            end
            local available = tonumber(args and args.availableItemCount) or 1
            if available < 1 then
                available = 1
            end
            if target > available then
                target = available
            end
            local rollsCount = tonumber(args and args.rollsCount)
            if rollsCount and target > rollsCount then
                target = rollsCount
            end
            return {
                target = target,
                available = available,
            }
        end,
        ValidateInventoryTradeSelection = function(_, args)
            local target = tonumber(args and args.target) or 1
            local selectedCount = tonumber(args and args.selectedCount) or 0
            local pickedCount = tonumber(args and args.pickedCount) or 0
            if selectedCount <= 0 then
                return {
                    ok = false,
                    errType = "empty_selection",
                }
            end
            if pickedCount < target then
                return {
                    ok = false,
                    errType = "not_enough_selection",
                    wantedCount = target,
                    pickedCount = pickedCount,
                }
            end
            return { ok = true }
        end,
        BuildMultiAwardWinnersPlan = function(_, args)
            local target = tonumber(args and args.target) or 1
            local selectedCount = tonumber(args and args.selectedCount) or 0
            local picked = (args and type(args.pickedWinners) == "table") and args.pickedWinners or {}
            if selectedCount <= 0 then
                return {
                    errType = "empty_selection",
                }
            end
            local awardCount = selectedCount
            if awardCount > target then
                awardCount = target
            end
            if #picked < awardCount then
                return {
                    errType = "not_enough_selection",
                    wantedCount = awardCount,
                    pickedCount = #picked,
                }
            end
            local winners = {}
            for i = 1, awardCount do
                winners[#winners + 1] = {
                    name = picked[i].name,
                    roll = tonumber(picked[i].roll) or 0,
                }
            end
            return {
                winners = winners,
                clearSelection = true,
            }
        end,
        BuildMultiAwardState = function(_, args)
            local winners = (args and type(args.winners) == "table") and args.winners or {}
            return {
                state = {
                    active = true,
                    itemLink = args and args.itemLink,
                    itemKey = h.addon.Item.GetItemStringFromLink(args and args.itemLink) or (args and args.itemLink),
                    lastCount = tonumber(args and args.available) or 1,
                    rollType = args and args.rollType,
                    winners = winners,
                    currentWinner = winners[1] and winners[1].name or nil,
                    pos = 2,
                    total = #winners,
                    slotCandidates = args and args.slotCandidates or {},
                    slotCandidateMap = args and args.slotCandidateMap or {},
                    lastClearedSlot = nil,
                    waitingForDecrement = false,
                    announceOnWin = args and args.announceOnWin and true or false,
                    congratsSent = false,
                },
            }
        end,
        IsMasterLootAwardFailureMessage = function(_, message)
            return tostring(message or ""):lower():find("inventory is full", 1, true) ~= nil
        end,
    }
    h.addon.Services.Raid = {
        IsMasterLooter = function()
            return true
        end,
        GetRosterVersion = function()
            return 1
        end,
        RequestMasterLootCandidateRefresh = function()
            candidateCache.itemLink = nil
            table.wipe(candidateCache.indexByName)
        end,
        FindMasterLootCandidateIndex = function(_, itemLinkArg, playerName)
            local cache = candidateCache
            if cache.itemLink ~= itemLinkArg then
                cache = rebuildCandidateCache(itemLinkArg)
            end
            local candidateIndex = cache.indexByName[playerName]
            if not candidateIndex then
                cache = rebuildCandidateCache(itemLinkArg)
                candidateIndex = cache.indexByName[playerName]
            end
            return candidateIndex
        end,
        CanResolveMasterLootCandidates = function(_, itemLinkArg)
            local cache = candidateCache
            if cache.itemLink ~= itemLinkArg then
                cache = rebuildCandidateCache(itemLinkArg)
            end
            return next(cache.indexByName) ~= nil
        end,
        AddPlayerCountForRollType = function(_, playerName, rollType, count)
            addCounts[#addCounts + 1] = {
                name = playerName,
                rollType = rollType,
                count = count,
            }
        end,
        GetUnitID = function(_, playerName)
            local units = cfg.unitsByName or {}
            if units[playerName] ~= nil then
                return units[playerName]
            end
            return playerName and "raid1" or "none"
        end,
        ClearRaidIcons = function() end,
    }
    h.addon.Services.Rolls = {
        GetRollSession = function()
            return h.feature.lootState.rollSession
        end,
        SyncSessionState = function(_, session)
            h.feature.lootState.rollSession = session
        end,
        GetHighestRoll = function(_, winnerName)
            local rollsByName = cfg.rollsByName or {}
            return rollsByName[winnerName] or 0
        end,
        GetDisplayModel = function()
            return currentModel
        end,
        ValidateWinner = function(_, playerName, itemLinkArg, rollType)
            local provider = cfg.getEligibility or function()
                return { ok = true }
            end
            local result
            validationCalls[#validationCalls + 1] = {
                playerName = playerName,
                itemLink = itemLinkArg,
                rollType = rollType,
            }
            result = provider(playerName, itemLinkArg, rollType, currentModel) or { ok = false }
            if result.ok ~= true and not result.warnMessage then
                if result.reason == "manual_exclusion" then
                    result.warnMessage = h.addon.L.ErrMLWinnerExcluded:format(tostring(playerName))
                elseif result.reason == "not_in_raid" then
                    result.warnMessage = h.addon.L.ErrMLWinnerNotInRaid:format(tostring(playerName))
                elseif result.reason == "name_unresolved" then
                    result.warnMessage = h.addon.L.ErrMLWinnerNameUnresolved
                else
                    result.warnMessage = h.addon.L.ErrMLWinnerIneligible:format(tostring(playerName))
                end
            end
            return result
        end,
        ClearRolls = function() end,
        SetRollRecordingEnabled = function() end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.Database.GetRaidStoreOrNil = function()
        return {
            GetRaidByIndex = function(_, raidId)
                if raidId == 1 then
                    return raidRecord
                end
                return nil
            end,
        }
    end
    h.feature.Services = h.addon.Services
    h.feature.RAID_TARGET_MARKERS = h.C.RAID_TARGET_MARKERS

    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.feature.lootState.lootCount = cfg.lootCount or 1
    h.feature.lootState.rollsCount = cfg.rollsCount or #((currentModel and currentModel.rows) or {})
    h.feature.lootState.selectedItemCount = cfg.selectedItemCount or 1
    h.feature.lootState.currentRollType = cfg.rollType or h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = cfg.fromInventory == true
    h.feature.lootState.winner = nil

    return {
        h = h,
        Master = Master,
        link = link,
        setModel = function(model)
            currentModel = model
        end,
        getModel = function()
            return currentModel
        end,
        queuedAwards = queuedAwards,
        givenLoot = givenLoot,
        addCounts = addCounts,
        validationCalls = validationCalls,
        raid = raidRecord,
        getRefreshCount = function()
            return refreshCount
        end,
    }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("release stabilization tests use namespace option helpers", function()
    local source = readText("tests/release_stabilization_spec.lua")
    assertTextNotContains(source, "h.addon." .. "options", "tests must use namespace cfg:Get/cfg:Set instead of direct option table access")
    assertTextNotContains(source, "h.addon.Options." .. "Set(", "tests must use namespace cfg:Set instead of flat option writes")
end)

test("init forwards master loot list events through the KRT bus", function()
    local source = readText("!KRT/Init.lua")

    assertTextContains(source, "OPEN_MASTER_LOOT_LIST", "expected Init.lua to register the master loot list open event")
    assertTextContains(source, "UPDATE_MASTER_LOOT_LIST", "expected Init.lua to register the master loot list update event")
    assertTextContains(source, "WowEvents.OpenMasterLootList", "expected Init.lua to forward master loot list open events")
    assertTextContains(source, "WowEvents.UpdateMasterLootList", "expected Init.lua to forward master loot list update events")
end)

test("runtime cache reuses runtime until invalidated", function()
    local h = newHarness()
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
        },
        bossKills = {
            { bossNid = 1, boss = "Boss" },
        },
        loot = {
            { lootNid = 1, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 2,
        nextBossNid = 2,
        nextLootNid = 2,
    }

    local runtime1 = store:EnsureRaidRuntime(raid)
    local runtime2 = store:EnsureRaidRuntime(raid)
    assertTrue(runtime1 ~= nil, "expected runtime to be created")
    assertTrue(runtime1 == runtime2, "expected second lookup to reuse runtime table")

    raid.loot[#raid.loot + 1] = { lootNid = 2, itemId = 9002, looterNid = 1 }
    store:StripRuntime(raid)
    local runtime3 = store:EnsureRaidRuntime(raid)
    assertTrue(runtime3 ~= runtime1, "expected invalidation to rebuild runtime table")
    assertEqual(runtime3.lootIdxByNid[2], 2, "expected rebuilt loot index to include new loot")
end)

test("raid schema version includes shared loot source candidate migration", function()
    local h = newHarness()
    h:load("!KRT/Database/DBSchema.lua")

    assertEqual(h.Database.GetRaidSchemaVersion(), 6, "expected shared source candidate migration to bump raid schema")
end)

test("raid store migrates legacy shared source labels to compact loot candidates", function()
    local h = newHarness()
    _G.KRT_Raids = {
        {
            schemaVersion = 5,
            raidNid = 100,
            players = {},
            bossKills = {
                {
                    bossNid = 7,
                    name = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                    sourceKind = "shared",
                    source = "LootSources",
                },
            },
            loot = {
                {
                    lootNid = 1,
                    bossNid = 7,
                    itemId = 91732,
                    itemName = "Resolver Ambiguous Charm",
                    lootSource = {
                        kind = "shared",
                        bossNid = 7,
                        sourceNpcId = 0,
                        sourceName = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                    },
                },
            },
            changes = {},
            attendance = {},
            nextPlayerNid = 1,
            nextBossNid = 8,
            nextLootNid = 2,
        },
    }
    h.Database.GetRaidSchemaVersion = function()
        return 6
    end
    h:load("!KRT/Database/DBRaidMigrations.lua")
    h.Database.GetRaidMigrations = function()
        return h.addon.DB.RaidMigrations
    end
    h:load("!KRT/Database/DBRaidStore.lua")

    local store = h.addon.DB.RaidStore
    store:NormalizeAllRaids()
    local raid = _G.KRT_Raids[1]

    assertEqual(raid.schemaVersion, 6, "expected migrated raid to move to current schema")
    assertEqual(raid.bossKills[1].name, "Shared", "expected legacy shared boss label to be compacted")
    assertEqual(raid.loot[1].lootSource.sourceName, "Shared", "expected legacy loot source label to be compacted")
    assertTrue(type(raid.loot[1].lootSource.candidates) == "table", "expected migration to create shared candidates")
    assertEqual(#raid.loot[1].lootSource.candidates, 2, "expected both legacy shared bosses to become candidates")
    assertEqual(raid.loot[1].lootSource.candidates[1].name, "Grand Widow Faerlina", "expected first shared candidate name")
    assertEqual(raid.loot[1].lootSource.candidates[2].name, "Noth the Plaguebringer", "expected second shared candidate name")
end)

test("raid store migrates compact shared rows through item id source resolver", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [91732] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })
    _G.KRT_Raids = {
        {
            schemaVersion = 5,
            raidNid = 101,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {
                {
                    bossNid = 7,
                    name = "Shared",
                    sourceKind = "shared",
                    source = "LootSources",
                },
            },
            loot = {
                {
                    lootNid = 1,
                    bossNid = 7,
                    itemId = 91732,
                    itemName = "Resolver Ambiguous Charm",
                    lootSource = {
                        kind = "shared",
                        bossNid = 7,
                        sourceNpcId = 0,
                        sourceName = "Shared",
                    },
                },
            },
            changes = {},
            attendance = {},
            nextPlayerNid = 1,
            nextBossNid = 8,
            nextLootNid = 2,
        },
    }
    h.Database.GetRaidSchemaVersion = function()
        return 6
    end
    h:load("!KRT/Database/DBRaidMigrations.lua")
    h.Database.GetRaidMigrations = function()
        return h.addon.DB.RaidMigrations
    end
    h:load("!KRT/Database/DBRaidStore.lua")

    local store = h.addon.DB.RaidStore
    store:NormalizeAllRaids()
    local raid = _G.KRT_Raids[1]
    local lootSource = raid.loot[1].lootSource

    assertEqual(raid.schemaVersion, 6, "expected migrated raid to move to current schema")
    assertEqual(lootSource.sourceName, "Shared", "expected compact shared source label to remain compact")
    assertTextContains(lootSource.sourceKey, "shared|", "expected item-id migration to keep the shared source key")
    assertTrue(type(lootSource.candidates) == "table", "expected item-id migration to create shared candidates")
    assertEqual(#lootSource.candidates, 2, "expected both resolver candidates to be migrated")
    assertEqual(lootSource.candidates[1].name, "Grand Widow Faerlina", "expected first resolver candidate")
    assertEqual(lootSource.candidates[1].sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected first resolver candidate source key")
    assertEqual(lootSource.candidates[2].name, "Noth the Plaguebringer", "expected second resolver candidate")
    assertEqual(lootSource.candidates[2].sourceKey, "naxxramas|boss|15954|noth the plaguebringer|any", "expected second resolver candidate source key")
end)

test("runtime cache indexes appended loot without rebuilding runtime", function()
    local h = newHarness()
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
        },
        bossKills = {
            { bossNid = 1, boss = "Boss" },
        },
        loot = {
            { lootNid = 1, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 2,
        nextBossNid = 2,
        nextLootNid = 2,
    }

    local runtime1 = store:EnsureRaidRuntime(raid)
    local appended = { lootNid = 2, itemId = 9002, looterNid = 1 }
    raid.loot[#raid.loot + 1] = appended

    local runtime2 = store:UpsertLootIndex(raid, appended, #raid.loot)
    local runtime3 = store:EnsureRaidRuntime(raid)

    assertTrue(runtime2 == runtime1, "expected appended loot to update the existing runtime table")
    assertTrue(runtime3 == runtime1, "expected runtime lookup to avoid a full rebuild after indexed append")
    assertEqual(runtime1.lootIdxByNid[2], 2, "expected appended loot index to be patched")
    assertTrue(runtime1.lootByNid[2] == appended, "expected appended loot row to be indexed by nid")
end)

test("runtime cache builds logger history query indexes", function()
    local h = newHarness()
    local store = h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", countMS = 0 },
                { playerNid = 2, name = "Bob", class = "WARRIOR", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", players = { 1, 2 } },
                { bossNid = 11, name = "Grobbulus", players = { 2 } },
            },
            loot = {
                { lootNid = 101, bossNid = 10, itemId = 9001, looterNid = 1 },
                { lootNid = 102, bossNid = 11, itemId = 9002, looterNid = 2 },
                { lootNid = 103, bossNid = 10, itemId = 9003, looterNid = 1 },
            },
            attendance = {
                { playerNid = 1, segments = { { startTime = 1000, endTime = 1060 } } },
                { playerNid = 2, segments = { { startTime = 1000, endTime = 1120 } } },
            },
            nextPlayerNid = 3,
            nextBossNid = 12,
            nextLootNid = 104,
        },
    })

    local raid = h.Database.EnsureRaidById(1)
    local runtime = store:EnsureRaidRuntime(raid)

    assertTrue(runtime.playerByNid[1] == raid.players[1], "expected runtime player lookup by nid")
    assertEqual(runtime.playerNidByName.Alice, 1, "expected runtime player name lookup")
    assertEqual(runtime.attendanceIdxByPlayerNid[1], 1, "expected runtime attendance index by player nid")
    assertTrue(runtime.attendanceByPlayerNid[2] == raid.attendance[2], "expected runtime attendance row lookup")
    assertTrue(runtime.bossPlayerSetByBossNid[10][1] == true, "expected runtime boss attendee set")
    assertTrue(runtime.bossPlayerSetByBossNid[10][2] == true, "expected runtime boss attendee set to include all attendees")
    assertEqual(runtime.lootIdxByBossNid[10][1], 1, "expected first boss loot index")
    assertEqual(runtime.lootIdxByBossNid[10][2], 3, "expected second boss loot index")
    assertEqual(runtime.lootIdxByLooterNid[1][1], 1, "expected first player loot index")
    assertEqual(runtime.lootIdxByLooterNid[1][2], 3, "expected second player loot index")

    local appended = { lootNid = 104, bossNid = 10, itemId = 9004, looterNid = 2 }
    raid.loot[#raid.loot + 1] = appended
    local patched = store:UpsertLootIndex(raid, appended, #raid.loot)

    assertTrue(patched == runtime, "expected appended loot to patch the existing runtime table")
    assertEqual(runtime.lootIdxByBossNid[10][3], 4, "expected appended boss loot index to be patched")
    assertEqual(runtime.lootIdxByLooterNid[2][2], 4, "expected appended looter loot index to be patched")
end)

test("runtime cache upsert moves loot index between boss and looter maps", function()
    local h = newHarness()
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
            { playerNid = 2, name = "Bob", countMS = 0 },
        },
        bossKills = {
            { bossNid = 10, name = "Patchwerk" },
            { bossNid = 20, name = "Grobbulus" },
        },
        loot = {
            { lootNid = 101, bossNid = 10, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 3,
        nextBossNid = 21,
        nextLootNid = 102,
    }

    local function hasListValue(list, value)
        if type(list) ~= "table" then
            return false
        end
        for i = 1, #list do
            if list[i] == value then
                return true
            end
        end
        return false
    end

    local runtime1 = store:EnsureRaidRuntime(raid)
    local row = raid.loot[1]
    row.bossNid = 20
    row.looterNid = 2

    local runtime2 = store:UpsertLootIndex(raid, row, 1)
    local runtime3 = store:EnsureRaidRuntime(raid)

    assertTrue(runtime2 == runtime1, "expected upsert to patch the existing runtime table")
    assertTrue(runtime3 == runtime1, "expected patched signature to avoid a full rebuild")
    assertTrue(not hasListValue(runtime1.lootIdxByBossNid[10], 1), "expected old boss index to be cleared")
    assertTrue(hasListValue(runtime1.lootIdxByBossNid[20], 1), "expected new boss index to be added")
    assertTrue(not hasListValue(runtime1.lootIdxByLooterNid[1], 1), "expected old looter index to be cleared")
    assertTrue(hasListValue(runtime1.lootIdxByLooterNid[2], 1), "expected new looter index to be added")
    assertTrue(runtime1.lootByNid[101] == row, "expected loot nid lookup to stay attached to the row")
end)

test("runtime cache rebuilds when signature changes without explicit strip", function()
    local h = newHarness()
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
        },
        bossKills = {
            { bossNid = 1, boss = "Boss" },
        },
        loot = {
            { lootNid = 1, itemId = 9001, looterNid = 1 },
        },
        nextPlayerNid = 2,
        nextBossNid = 2,
        nextLootNid = 2,
    }

    local runtime1 = store:EnsureRaidRuntime(raid)
    raid.loot[#raid.loot + 1] = { lootNid = 2, itemId = 9002, looterNid = 1 }
    raid.nextLootNid = 3

    local runtime2 = store:EnsureRaidRuntime(raid)

    assertTrue(runtime2 == runtime1, "expected runtime table to be reused while rebuilding maps")
    assertEqual(runtime2.lootIdxByNid[2], 2, "expected signature mismatch to rebuild stale loot index")

    raid.nextLootNid = 4
    runtime2.signature = "stale"
    local runtime3 = store:EnsureRaidRuntime(raid)
    assertTrue(runtime3 == runtime1, "expected counter-only signature drift to rebuild in place")
    assertTrue(runtime3.signature ~= "stale", "expected runtime signature to be refreshed")
end)

test("raid insert preserves unique raid nid and replaces duplicate raid nid", function()
    local h = newHarness()
    _G.KRT_Raids = {
        {
            schemaVersion = 1,
            raidNid = 10,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            attendance = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    }
    h:load("!KRT/Database/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore

    local uniqueRaid = store:CreateRaidRecord({ raidNid = 42 })
    local insertedUnique, uniqueIndex = store:InsertRaid(uniqueRaid)
    assertEqual(insertedUnique.raidNid, 42, "expected unique positive raid nid to be preserved")
    assertEqual(uniqueIndex, 2, "expected unique raid to append after existing raid")

    local duplicateRaid = {
        schemaVersion = 1,
        raidNid = 42,
        players = {},
        bossKills = {},
        loot = {},
        changes = {},
        attendance = {},
        nextPlayerNid = 1,
        nextBossNid = 1,
        nextLootNid = 1,
    }
    local insertedDuplicate, duplicateIndex = store:InsertRaid(duplicateRaid)
    assertTrue(insertedDuplicate.raidNid ~= 42, "expected duplicate raid nid to be replaced")
    assertTrue(tonumber(insertedDuplicate.raidNid) > 0, "expected replacement raid nid to stay positive")
    assertEqual(duplicateIndex, 3, "expected duplicate raid to append after replacement")
    assertEqual(_G.KRT_Raids[2].raidNid, 42, "expected original unique raid nid to remain unchanged")

    local invalidRaid = {
        schemaVersion = 1,
        raidNid = 0,
        players = {},
        bossKills = {},
        loot = {},
        changes = {},
        attendance = {},
        nextPlayerNid = 1,
        nextBossNid = 1,
        nextLootNid = 1,
    }
    local insertedInvalid, invalidIndex = store:InsertRaid(invalidRaid)
    assertTrue(tonumber(insertedInvalid.raidNid) > 0, "expected invalid raid nid to be replaced")
    assertEqual(invalidIndex, 4, "expected invalid-nid raid to append after replacement")
end)

test("raid nid index cache repairs same-count duplicate drift", function()
    local h = newHarness()
    local store = h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            attendance = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 2,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            attendance = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })

    assertTrue(store:GetRaidByNid(1) ~= nil, "expected initial lookup to warm raid nid index")
    _G.KRT_Raids[2].raidNid = 1

    local firstRaid, firstIndex = store:GetRaidByNid(1)
    local secondRaid, secondIndex = store:GetRaidByIndex(2)

    assertEqual(firstIndex, 1, "expected original raid nid lookup to remain stable")
    assertTrue(firstRaid == _G.KRT_Raids[1], "expected first raid to remain indexed by nid 1")
    assertEqual(secondIndex, 2, "expected second raid to remain addressable by index")
    assertTrue(tonumber(secondRaid.raidNid) ~= 1, "expected duplicate raid nid drift to be repaired")
end)

test("raid validator skips runtime clone and reports root runtime keys", function()
    local h = newHarness()
    local normalizedRuntime = nil
    local fakeStore = {
        NormalizeRaidRecord = function(_, raid)
            normalizedRuntime = raid._runtime
            raid.players = (type(raid.players) == "table") and raid.players or {}
            raid.bossKills = (type(raid.bossKills) == "table") and raid.bossKills or {}
            raid.loot = (type(raid.loot) == "table") and raid.loot or {}
            raid.changes = (type(raid.changes) == "table") and raid.changes or {}
            raid.attendance = (type(raid.attendance) == "table") and raid.attendance or {}
            raid.nextPlayerNid = tonumber(raid.nextPlayerNid) or 2
            raid.nextBossNid = tonumber(raid.nextBossNid) or 1
            raid.nextLootNid = tonumber(raid.nextLootNid) or 1
            return raid
        end,
    }
    h.Database.GetRaidStoreOrNil = function()
        return fakeStore
    end
    h:load("!KRT/Database/DBRaidValidator.lua")

    local result = h.addon.DB.RaidValidator:GetRaidRecordValidation({
        schemaVersion = 1,
        raidNid = 1,
        _runtime = {
            playersByName = {
                Alice = true,
            },
        },
        _playersByName = {
            Alice = true,
        },
        players = {
            { playerNid = 1, name = "Alice", countMS = 0 },
        },
        bossKills = {},
        loot = {},
        changes = {},
        attendance = {},
        nextPlayerNid = 2,
        nextBossNid = 1,
        nextLootNid = 1,
    }, 1, 1)

    local sawRootRuntime = false
    local sawRuntimeCloneError = false
    for i = 1, #result.details do
        local detail = result.details[i]
        local key = detail.data and detail.data.key
        if detail.code == "RUNTIME_OUTSIDE" and key == "_playersByName" then
            sawRootRuntime = true
        elseif detail.code == "RUNTIME_OUTSIDE" and key == "_runtime" then
            sawRuntimeCloneError = true
        end
    end

    assertTrue(normalizedRuntime == nil, "expected validator clone to omit derived runtime maps")
    assertTrue(sawRootRuntime == true, "expected validator to report root runtime keys")
    assertTrue(sawRuntimeCloneError ~= true, "expected validator to allow current runtime clone key")
end)

test("feature shared hydrates addon dependencies and namespace helpers", function()
    local h = newHarness()
    local strings = { marker = true }

    h.addon.Strings = strings
    h.feature.Strings = nil
    h.addon.Services.Rolls = nil

    local feature = h.Database.GetFeatureShared()
    local rolls = feature.EnsureServiceNamespace("Rolls")

    assertTrue(feature.Strings == strings, "expected shared feature table to hydrate addon dependency")
    assertTrue(rolls == h.addon.Services.Rolls, "expected service namespace helper to create addon.Services.Rolls")
    assertTrue(h.Database.EnsureServiceNamespace("Rolls") == rolls, "expected Database helper to return the same service namespace")
end)

test("raid roster update records joins leaves and player metadata", function()
    local h = newHarness()
    h.feature.L.RaidZones = { Naxxramas = true }
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            nextPlayerNid = 3,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", join = 900, countMS = 2 },
                { playerNid = 2, name = "Bob", rank = 0, subgroup = 2, class = "WARRIOR", join = 900, countMS = 0 },
            },
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetRealmName = function()
        return "TestRealm"
    end
    h.addon.IsInRaid = function()
        return true
    end
    h.addon.IsInGroup = function()
        return true
    end
    _G.KRT_Players = {}
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 4
    end
    _G.GetNumRaidMembers = function()
        return 2
    end
    _G.GetRaidRosterInfo = function(index)
        if index == 1 then
            return "Alice", 1, 1, 80, "Mage", "MAGE"
        end
        if index == 2 then
            return "Cara", 0, 3, 80, "Priest", "PRIEST"
        end
        return nil
    end
    _G.UnitRace = function(unit)
        if unit == "raid2" then
            return "Human", "Human"
        end
        return "Gnome", "Gnome"
    end
    _G.UnitSex = function()
        return 2
    end

    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    local rosterChanged, delta = Raid:UpdateRaidRoster()
    local raid = h.Database.EnsureRaidById(1)

    assertTrue(rosterChanged == true, "expected roster update to report a join/leave change")
    assertEqual(delta.joined[1].name, "Cara", "expected Cara to be reported as joined")
    assertEqual(delta.left[1].name, "Bob", "expected Bob to be reported as left")
    assertTrue(delta.updated == nil, "expected unchanged Alice to avoid an update delta")
    assertEqual(raid.players[1].name, "Alice", "expected Alice to stay in roster")
    assertEqual(raid.players[1].countMS, 2, "expected existing loot count to be preserved")
    assertEqual(raid.players[2].name, "Bob", "expected Bob row to stay persisted")
    assertTrue(tonumber(raid.players[2].leave) == 1000, "expected Bob to be marked left")
    assertEqual(raid.players[3].name, "Cara", "expected Cara to be added to roster")
    assertEqual(_G.KRT_Players.TestRealm.Cara.class, "PRIEST", "expected realm player metadata to be updated")
end)

test("auto master loot and group loot restore default off", function()
    local h = newHarness()
    local setLootMethodCalls = {}

    _G.GetTime = function()
        return 1000
    end
    _G.GetLootMethod = function()
        return "group"
    end
    _G.SetLootMethod = function(...)
        setLootMethodCalls[#setLootMethodCalls + 1] = { ... }
    end
    _G.UnitExists = function(unit)
        return unit == "target"
    end
    _G.UnitGUID = function(unit)
        return unit == "target" and "Creature-0-0-0-0-15956-0000000000" or nil
    end
    _G.UnitInRaid = function(unit)
        return unit == "player"
    end
    _G.UnitIsDead = function()
        return false
    end
    _G.UnitName = function(unit)
        return unit == "player" and "Tester" or nil
    end
    h.feature.BossIDs = {
        BossIDs = {
            [15956] = true,
        },
    }
    h.feature.GetCreatureId = function()
        return 15956
    end
    h:setRaidRoleState({
        isLeader = true,
        isMasterLooter = false,
        inRaid = true,
    })

    h:load("!KRT/Services/Raid.lua")

    local masterCfg = h.addon.Options.Get("Master")
    assertEqual(masterCfg:Get("autoMasterLootOnBossTarget"), false, "expected Auto Master Loot to default off")
    assertEqual(masterCfg:Get("askGroupLootAfterBossLoot"), false, "expected Group Loot restore prompt to default off")
    assertEqual(masterCfg:GetDefaults().autoMasterLootOnBossTarget, false, "expected Auto Master Loot default contract to be off")
    assertEqual(masterCfg:GetDefaults().askGroupLootAfterBossLoot, false, "expected Group Loot restore default contract to be off")
    assertEqual(h.addon.Services.Raid:HandleAutoMasterLootTargetChanged(), false, "expected default-off Auto Master Loot to stay inert")
    assertEqual(#setLootMethodCalls, 0, "expected default-off Auto Master Loot not to call SetLootMethod")
end)

test("group loot restore prompt is emitted through the master ui event", function()
    local h = newHarness()
    local lootMethod = "master"
    local promptCount = 0
    local popupCount = 0

    _G.GetLootMethod = function()
        return lootMethod
    end
    _G.SetLootMethod = function(method)
        lootMethod = method
    end
    _G.StaticPopup_Show = function()
        popupCount = popupCount + 1
    end
    _G.UnitExists = function(unit)
        return unit == "target"
    end
    _G.UnitGUID = function(unit)
        return unit == "target" and "Creature-0-0-0-0-15956-0000000000" or nil
    end
    _G.UnitInRaid = function(unit)
        return unit == "player"
    end
    _G.UnitIsDead = function()
        return true
    end
    _G.UnitName = function(unit)
        return unit == "player" and "Tester" or "Anub'Rekhan"
    end
    h.addon.IsInRaid = function()
        return true
    end
    h.Database.GetUnitRank = function(unit)
        return unit == "player" and 2 or 0
    end
    h.feature.BossIDs = {
        BossIDs = {
            [15956] = true,
        },
    }
    h.feature.GetCreatureId = function()
        return 15956
    end
    h:setRaidRoleState({
        isLeader = true,
        isMasterLooter = true,
        inRaid = true,
    })

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local masterCfg = h.addon.Options.Get("Master")
    masterCfg:Set("askGroupLootAfterBossLoot", true)
    h.Bus.RegisterCallback(h.addon.Events.Internal.RequestGroupLootRestorePrompt, function()
        promptCount = promptCount + 1
    end)

    assertEqual(Raid:NotifyLootWindowOpened(), true, "expected boss Master Loot window to arm restore prompt")
    assertEqual(Raid:NotifyLootWindowCleared(), true, "expected cleared boss loot to request restore prompt")
    assertEqual(promptCount, 1, "expected service to publish the UI-owned restore prompt event")
    assertEqual(popupCount, 0, "expected service not to call StaticPopup_Show directly")
    assertEqual(Raid:NotifyLootWindowCleared(), false, "expected prompt request to stay single-shot")
    assertEqual(promptCount, 1, "expected duplicate cleared notifications not to publish another prompt")
end)

test("raid roster update preserves previous names for temporary unknown units", function()
    local h = newHarness()
    h.feature.L.RaidZones = { Naxxramas = true }
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            nextPlayerNid = 2,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", join = 900, countMS = 1 },
            },
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetRealmName = function()
        return "TestRealm"
    end
    h.addon.IsInRaid = function()
        return true
    end
    _G.KRT_Players = {}
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 4
    end
    _G.GetNumRaidMembers = function()
        return 1
    end
    local rosterName = "Alice"
    _G.GetRaidRosterInfo = function()
        return rosterName, 1, 1, 80, "Mage", "MAGE"
    end
    _G.UnitRace = function()
        return "Gnome", "Gnome"
    end
    _G.UnitSex = function()
        return 2
    end

    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    local firstChanged = Raid:UpdateRaidRoster()
    assertTrue(firstChanged == true, "expected initial roster size sync to report a change")

    rosterName = _G.UNKNOWNOBJECT
    local secondChanged, delta = Raid:UpdateRaidRoster()
    local raid = h.Database.EnsureRaidById(1)

    assertTrue(secondChanged ~= true, "expected temporary unknown unit to avoid roster churn")
    assertEqual(delta.unresolved[1].unitID, "raid1", "expected unresolved unit to be reported")
    assertEqual(delta.unresolved[1].name, "Alice", "expected previous live name to be preserved")
    assertTrue(raid.players[1].leave == nil, "expected Alice not to be marked left while unit is unknown")
    assertEqual(h.timerCount(), 1, "expected unknown unit retry to be scheduled")
end)

test("raid attendance records roster delta segments by player nid", function()
    local h = newHarness()

    h:installRaidStore({
        {
            schemaVersion = 4,
            raidNid = 1,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 1,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", countMS = 0 },
            },
            attendance = {},
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.addon.State.currentRaid = 1

    h:load("!KRT/Services/Raid.lua")

    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidRosterDelta, {
        raidNum = 1,
        timestamp = 1000,
        joined = {
            { playerNid = 1, name = "Alice", subgroup = 1, online = true },
        },
    }, 1, 1)
    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidRosterDelta, {
        raidNum = 1,
        timestamp = 1010,
        updated = {
            { playerNid = 1, name = "Alice", subgroup = 2, online = false },
        },
    }, 2, 1)
    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidRosterDelta, {
        raidNum = 1,
        timestamp = 1030,
        left = {
            { playerNid = 1, name = "Alice", subgroup = 2, online = false },
        },
    }, 3, 1)

    local raid = h.Database.EnsureRaidById(1)
    local Raid = h.addon.Services.Raid
    local entry = Raid:GetAttendanceEntry(raid, 1)
    assertTrue(entry ~= nil, "expected attendance entry to be created for Alice")
    assertEqual(entry.playerNid, 1, "expected attendance to use playerNid instead of player name keys")
    assertEqual(#entry.segments, 2, "expected online transition to split attendance segments")
    assertEqual(entry.segments[1].startTime, 1000, "expected first attendance segment to start on join")
    assertEqual(entry.segments[1].endTime, 1010, "expected first attendance segment to close on online change")
    assertTrue(entry.segments[1].online ~= false, "expected omitted online flag to mean online")
    assertEqual(entry.segments[2].startTime, 1010, "expected second attendance segment to start on update")
    assertEqual(entry.segments[2].endTime, 1030, "expected second attendance segment to close on leave")
    assertEqual(entry.segments[2].subgroup, 2, "expected subgroup changes to be stored on the segment")
    assertEqual(entry.segments[2].online, false, "expected offline state to be stored on the segment")
end)

test("db syncer routes requests through whisper and group transports", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
        },
    })

    local whisperMessages = {}
    local groupMessages = {}

    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.addon.IsInGroup = function()
        return true
    end
    h.addon.IsInRaid = function()
        return false
    end
    h.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        whisperMessages[#whisperMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Database/DBSyncer.lua")
    h.addon.Comms.Sync = function(prefix, payload)
        groupMessages[#groupMessages + 1] = {
            prefix = prefix,
            payload = payload,
        }
    end
    local syncer = h.addon.DB.Syncer

    assertTrue(syncer:RequestLoggerReq(42, " Alice ") == true, "expected targeted logger request to send")
    assertEqual(#whisperMessages, 1, "expected one whisper transport message")
    assertEqual(whisperMessages[1].prefix, "KRTLogSync", "expected sync prefix on whisper")
    assertEqual(whisperMessages[1].channel, "WHISPER", "expected direct sync to use whisper transport")
    assertEqual(whisperMessages[1].target, "Alice", "expected target name to be normalized before whisper")
    local reqPrefix = table.concat({ "RQ", "1", "1", "REQ", "42" }, "\t")
    assertEqual(whisperMessages[1].payload:sub(1, #reqPrefix), reqPrefix, "expected request payload header to stay stable")

    assertTrue(syncer:RequestLoggerSync() == true, "expected current raid sync request to send")
    assertEqual(#groupMessages, 1, "expected one group transport message")
    assertEqual(groupMessages[1].prefix, "KRTLogSync", "expected sync prefix on group message")
    local syncPrefix = table.concat({ "RQ", "1", "2", "SYNC", "77", h.addon.Base64.Encode("Naxxramas"), "25", "4" }, "\t")
    assertEqual(groupMessages[1].payload:sub(1, #syncPrefix), syncPrefix, "expected sync payload header to stay stable")
end)

test("db syncer persistent logger sync schedules current raid sync when enabled", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
        },
    })

    local groupMessages = {}
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.addon.IsInGroup = function()
        return true
    end
    h.addon.IsInRaid = function()
        return true
    end
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Database/DBSyncer.lua")
    h.addon.Comms.Sync = function(prefix, payload)
        groupMessages[#groupMessages + 1] = {
            prefix = prefix,
            payload = payload,
        }
    end

    local syncer = h.addon.DB.Syncer
    setHarnessOption(h, "Logger", "persistentSync", true, { persistentSync = false })
    syncer:RefreshPersistentSync(0)
    h.addon._flushTimers()

    assertEqual(#groupMessages, 1, "expected persistent sync to send one current-raid sync request")
    assertEqual(groupMessages[1].prefix, "KRTLogSync", "expected persistent sync to use logger sync prefix")
end)

test("db syncer registers logger loot threshold defaults", function()
    local h = newHarness()

    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Database/DBSyncer.lua")

    assertEqual(getHarnessOption(h, "Logger", "ignoreSelectionThreshold"), true, "expected logger threshold override to be enabled by default")
    assertEqual(getHarnessOption(h, "Logger", "loggerLootQualityThreshold"), 4, "expected default logger threshold to be Epic")
end)

test("db syncer skips base64 work for empty snapshot text fields", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Alice", rank = 0, subgroup = 1, class = "", join = 1000, countMS = 0 },
            },
            bossKills = {},
            loot = {},
            changes = {
                Alice = "",
            },
        },
    })
    h.addon.IsInGroup = function()
        return true
    end
    h.addon.IsInRaid = function()
        return false
    end
    h.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")

    local originalEncode = h.addon.Base64.Encode
    local emptyEncodeCalls = 0
    h.addon.Base64.Encode = function(value)
        if value == nil or value == "" then
            emptyEncodeCalls = emptyEncodeCalls + 1
        end
        return originalEncode(value)
    end

    h:load("!KRT/Database/DBSyncer.lua")

    assertTrue(h.addon.DB.Syncer:BroadcastLoggerPush(77, "Alice") == true, "expected snapshot push to send")
    assertEqual(emptyEncodeCalls, 0, "expected empty snapshot fields to avoid Base64 encoding work")
end)

test("db syncer throttles passive cleanup but keeps request setup cleanup immediate", function()
    local now = 1000
    _G.GetTime = function()
        return now
    end

    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.addon.IsInGroup = function()
        return true
    end
    h.addon.IsInRaid = function()
        return false
    end
    h.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Database/DBSyncer.lua")

    local syncer = h.addon.DB.Syncer
    syncer:OnAddonMessage("KRTLogSync", table.concat({ "RQ", "1", "prime", "BAD" }, "\t"), "WHISPER", "Alice")

    syncer._incoming.stale = { createdAt = 0, requestId = "stale", mode = "PUSH" }
    syncer:OnAddonMessage("KRTLogSync", table.concat({ "RQ", "1", "second", "BAD" }, "\t"), "WHISPER", "Alice")
    assertTrue(syncer._incoming.stale ~= nil, "expected passive addon-message cleanup to be throttled")

    assertTrue(syncer:RequestLoggerReq(77, "Alice") == true, "expected request setup to continue after forced cleanup")
    assertTrue(syncer._incoming.stale == nil, "expected request setup path to force stale sync cleanup")
end)

test("db syncer rejects malformed snapshot payloads without importing", function()
    local cases = {
        {
            name = "first row not header",
            lines = function(enc)
                return {
                    table.concat({ "P", "1", enc("Alice"), "0", "1", enc("MAGE"), "1000", "0", "0" }, "\t"),
                    table.concat({ "H", "1", "1", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "2", "1", "1" }, "\t"),
                }
            end,
        },
        {
            name = "missing header",
            lines = function(enc)
                return {
                    table.concat({ "P", "1", enc("Alice"), "0", "1", enc("MAGE"), "1000", "0", "0" }, "\t"),
                }
            end,
        },
        {
            name = "duplicate header",
            lines = function(enc)
                return {
                    table.concat({ "H", "1", "1", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                    table.concat({ "H", "1", "1", "78", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                }
            end,
        },
        {
            name = "unknown row kind",
            lines = function(enc)
                return {
                    table.concat({ "H", "1", "1", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                    table.concat({ "X", "1" }, "\t"),
                }
            end,
        },
        {
            name = "future schema",
            lines = function(enc)
                return {
                    table.concat({ "H", "1", "2", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                }
            end,
        },
        {
            name = "truncated known row",
            lines = function(enc)
                return {
                    table.concat({ "H", "1", "1", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                    table.concat({ "P", "1" }, "\t"),
                }
            end,
        },
        {
            name = "invalid required nid",
            lines = function(enc)
                return {
                    table.concat({ "H", "1", "1", "77", enc("Naxxramas"), "25", "4", enc("TestRealm"), "1000", "0", "1", "1", "1" }, "\t"),
                    table.concat({ "P", "bad", enc("Alice"), "0", "1", enc("MAGE"), "1000", "0", "0" }, "\t"),
                }
            end,
        },
    }

    for i = 1, #cases do
        local case = cases[i]
        local h = newHarness()
        h:installRaidStore({
            {
                schemaVersion = 1,
                raidNid = 900,
                zone = "Existing",
                size = 10,
                difficulty = 1,
                realm = "TestRealm",
                startTime = 500,
                players = {},
                bossKills = {},
                loot = {},
                changes = {},
            },
        })
        h.addon.IsInGroup = function()
            return true
        end
        h.addon.IsInRaid = function()
            return false
        end
        h:load("!KRT/Modules/Comms.lua")
        h:load("!KRT/Modules/Base64.lua")
        h:load("!KRT/Database/DBSyncer.lua")

        local function enc(value)
            return h.addon.Base64.Encode(value)
        end

        local payload = table.concat(case.lines(enc), "\n")
        local encodedPayload = h.addon.Base64.Encode(payload)
        local msg = table.concat({ "SN", "1", "malformed-" .. i, "PUSH", "77", "1", "1", encodedPayload }, "\t")

        h.addon.DB.Syncer:OnAddonMessage("KRTLogSync", msg, "WHISPER", "Alice")

        assertEqual(#_G.KRT_Raids, 1, "expected malformed snapshot to avoid importing: " .. case.name)
        assertEqual(_G.KRT_Raids[1].raidNid, 900, "expected malformed snapshot to preserve existing raid nid: " .. case.name)
        assertEqual(_G.KRT_Raids[1].zone, "Existing", "expected malformed snapshot to preserve existing raid zone: " .. case.name)
        assertContains(h.logs.warn, "Diag.W.LogSyncParseFailed", "expected parse failure warning for malformed snapshot: " .. case.name)
    end
end)

test("db syncer imports push snapshots and merges requested sync chunks", function()
    local source = newHarness()
    local itemLink = source.registerItem(9001, "Sync Blade")
    local itemString = source.addon.Item.GetItemStringFromLink(itemLink)
    source:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 2, class = "MAGE", join = 1000, countMS = 3 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", mode = "n", difficulty = 4, time = 1010, hash = "patchwerk-1010", players = { 1 } },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9001,
                    itemName = "Sync Blade",
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = 4,
                    itemTexture = "Icon9001",
                    itemCount = 1,
                    looterNid = 1,
                    rollType = source.rollTypes.MAINSPEC,
                    rollValue = 98,
                    bossNid = 10,
                    time = 1015,
                },
            },
            changes = {
                Alice = "Fire",
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 102,
        },
    })

    local snapshotMessages = {}
    source.addon.IsInGroup = function()
        return true
    end
    source.addon.IsInRaid = function()
        return false
    end
    source.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        snapshotMessages[#snapshotMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end

    source:load("!KRT/Modules/Comms.lua")
    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Database/DBSyncer.lua")
    assertTrue(source.addon.DB.Syncer:BroadcastLoggerPush(77, "Bob") == true, "expected source push snapshot to send")
    assertTrue(#snapshotMessages > 1, "expected source snapshot to be chunked")

    local function rewriteSnapshotMessage(payload, requestId, mode, partIndex, partCount)
        local fields = {}
        for field in payload:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        fields[3] = requestId or fields[3]
        fields[4] = mode or fields[4]
        fields[6] = tostring(partIndex or fields[6])
        fields[7] = tostring(partCount or fields[7])
        return table.concat(fields, "\t")
    end

    local pushTarget = newHarness()
    pushTarget:installRaidStore({})
    pushTarget.addon.IsInGroup = function()
        return true
    end
    pushTarget.addon.IsInRaid = function()
        return false
    end
    pushTarget:load("!KRT/Modules/Comms.lua")
    pushTarget:load("!KRT/Modules/Base64.lua")
    pushTarget:load("!KRT/Database/DBSyncer.lua")

    local badChunk = table.concat({ "SN", "1", "bad", "PUSH", "77", "2", "1", "corrupt" }, "\t")
    pushTarget.addon.DB.Syncer:OnAddonMessage("KRTLogSync", badChunk, "WHISPER", "Alice")
    assertEqual(#_G.KRT_Raids, 0, "expected malformed chunk metadata to avoid importing a raid")
    assertContains(pushTarget.logs.warn, "Diag.W.LogSyncChunkMalformed", "expected malformed snapshot chunk to be reported")

    local changedCountId = "changed-count"
    local changedCountFirst = rewriteSnapshotMessage(snapshotMessages[1].payload, changedCountId, "PUSH", 1, #snapshotMessages)
    local changedCountSecond = rewriteSnapshotMessage(snapshotMessages[1].payload, changedCountId, "PUSH", 1, #snapshotMessages + 1)
    pushTarget.addon.DB.Syncer:OnAddonMessage(snapshotMessages[1].prefix, changedCountFirst, "WHISPER", "Alice")
    pushTarget.addon.DB.Syncer:OnAddonMessage(snapshotMessages[1].prefix, changedCountSecond, "WHISPER", "Alice")
    assertEqual(#_G.KRT_Raids, 0, "expected part-count changes to reset chunk assembly without import")
    assertContains(pushTarget.logs.warn, "Diag.W.LogSyncChunkPartCountChanged", "expected part-count changes to be reported")

    for i = 1, #snapshotMessages do
        local msg = snapshotMessages[i]
        pushTarget.addon.DB.Syncer:OnAddonMessage(msg.prefix, msg.payload, msg.channel, "Alice")
    end

    assertEqual(#_G.KRT_Raids, 1, "expected push snapshot to import one raid")
    assertEqual(_G.KRT_Raids[1].players[1].name, "Alice", "expected imported push snapshot to preserve players")
    assertEqual(_G.KRT_Raids[1].loot[1].rollValue, 98, "expected imported push snapshot to preserve loot roll values")
    assertEqual(_G.KRT_Raids[1].changes.Alice, nil, "expected imported push snapshot to drop retired changes data")

    local syncTarget = newHarness()
    syncTarget:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 700,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 900,
            players = {},
            bossKills = {},
            loot = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    syncTarget.Database.GetCurrentRaid = function()
        return 1
    end
    syncTarget.addon.IsInGroup = function()
        return true
    end
    syncTarget.addon.IsInRaid = function()
        return false
    end
    syncTarget:load("!KRT/Modules/Comms.lua")
    syncTarget:load("!KRT/Modules/Base64.lua")
    syncTarget:load("!KRT/Database/DBSyncer.lua")

    local groupMessages = {}
    syncTarget.addon.Comms.Sync = function(prefix, payload)
        groupMessages[#groupMessages + 1] = {
            prefix = prefix,
            payload = payload,
        }
    end

    assertTrue(syncTarget.addon.DB.Syncer:RequestLoggerSync() == true, "expected sync request to create pending state")
    assertEqual(#groupMessages, 1, "expected one outgoing sync request")
    local fields = {}
    for field in groupMessages[1].payload:gmatch("[^\t]+") do
        fields[#fields + 1] = field
    end
    local syncRequestId = fields[3]
    assertTrue(syncTarget.addon.DB.Syncer._pendingRequests[syncRequestId] ~= nil, "expected sync request to be pending")

    for i = 1, #snapshotMessages do
        local msg = snapshotMessages[i]
        local rewritten = rewriteSnapshotMessage(msg.payload, syncRequestId, "SYNC")
        syncTarget.addon.DB.Syncer:OnAddonMessage(msg.prefix, rewritten, "RAID", "Officer")
    end

    local mergedRaid = _G.KRT_Raids[1]
    assertEqual(#_G.KRT_Raids, 1, "expected requested sync to merge into the current raid")
    assertEqual(mergedRaid.raidNid, 700, "expected requested sync to preserve the local raid nid")
    assertEqual(mergedRaid.players[1].name, "Alice", "expected requested sync to merge players")
    assertEqual(mergedRaid.loot[1].lootNid, 101, "expected requested sync to merge loot by nid")
    assertEqual(mergedRaid.changes.Alice, nil, "expected requested sync to ignore retired changes data")
    assertTrue(syncTarget.addon.DB.Syncer._pendingRequests[syncRequestId] == nil, "expected successful sync merge to complete the pending request")
end)

test("db syncer snapshot payload uses nid references for repeated player fields", function()
    local source = newHarness()
    local itemLink = source.registerItem(9002, "Compact Sync Blade")
    local itemString = source.addon.Item.GetItemStringFromLink(itemLink)
    source:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 78,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Longplayernameone", rank = 1, subgroup = 2, class = "MAGE", join = 1000, countMS = 3 },
                { playerNid = 2, name = "Longplayernametwo", rank = 1, subgroup = 3, class = "PRIEST", join = 1000, countMS = 2 },
            },
            bossKills = {
                {
                    bossNid = 10,
                    name = "Patchwerk",
                    mode = "n",
                    difficulty = 4,
                    time = 1010,
                    hash = "patchwerk-1010",
                    players = { "Longplayernameone", "Longplayernametwo" },
                },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9002,
                    itemName = "Compact Sync Blade",
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = 4,
                    itemTexture = "Icon9002",
                    itemCount = 1,
                    looterNid = 1,
                    rollType = source.rollTypes.MAINSPEC,
                    rollValue = 98,
                    bossNid = 10,
                    time = 1015,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 11,
            nextLootNid = 102,
        },
    })

    local snapshotMessages = {}
    source.addon.IsInGroup = function()
        return true
    end
    source.addon.IsInRaid = function()
        return false
    end
    source.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        snapshotMessages[#snapshotMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end

    source:load("!KRT/Modules/Comms.lua")
    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Database/DBSyncer.lua")

    assertTrue(source.addon.DB.Syncer:BroadcastLoggerPush(78, "Bob") == true, "expected source push snapshot to send")

    local encodedParts = {}
    for i = 1, #snapshotMessages do
        local fields = {}
        for field in snapshotMessages[i].payload:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        encodedParts[tonumber(fields[6]) or i] = fields[8] or ""
    end

    local snapshotPayload = source.addon.Base64.Decode(table.concat(encodedParts, ""))
    assertTrue(type(snapshotPayload) == "string" and snapshotPayload ~= "", "expected decoded snapshot payload")

    local bossPlayers = nil
    local lootLooter = nil
    for line in snapshotPayload:gmatch("[^\n]+") do
        local fields = {}
        for field in line:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        if fields[1] == "B" then
            bossPlayers = source.addon.Base64.Decode(fields[8] or "")
        elseif fields[1] == "L" then
            lootLooter = source.addon.Base64.Decode(fields[10] or "")
        end
    end

    assertEqual(bossPlayers, table.concat({ "1", "2" }, string.char(31)), "expected boss attendee payload to use playerNid references")
    assertEqual(lootLooter, "1", "expected loot looter payload to use playerNid reference")
end)

test("db syncer resolves loot looter through current query facade", function()
    local source = newHarness()
    local itemLink = source.registerItem(9003, "Dynamic Query Sync Blade")
    local itemString = source.addon.Item.GetItemStringFromLink(itemLink)
    source:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 79,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 2, class = "MAGE", join = 1000, countMS = 3 },
            },
            bossKills = {},
            loot = {
                {
                    lootNid = 101,
                    itemId = 9003,
                    itemName = "Dynamic Query Sync Blade",
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = 4,
                    itemTexture = "Icon9003",
                    itemCount = 1,
                    rollType = source.rollTypes.MAINSPEC,
                    rollValue = 98,
                    bossNid = 0,
                    time = 1015,
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 102,
        },
    })

    local staleQueries = {
        ResolveLootLooterNameFromMap = function()
            return "Stale"
        end,
    }
    source.Database.GetRaidQueries = function()
        return staleQueries
    end

    local snapshotMessages = {}
    source.addon.IsInGroup = function()
        return true
    end
    source.addon.IsInRaid = function()
        return false
    end
    source.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        snapshotMessages[#snapshotMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end

    local currentQueries = {
        ResolveLootLooterNameFromMap = function(_, loot, playerNameByNid)
            assertEqual(tonumber(loot and loot.lootNid), 101, "expected current query to receive the loot row")
            return playerNameByNid[1] or ""
        end,
    }
    source:load("!KRT/Modules/Comms.lua")
    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Database/DBSyncer.lua")

    source.Database.GetRaidQueries = function()
        return currentQueries
    end
    source.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    assertTrue(source.addon.DB.Syncer:BroadcastLoggerPush(79, "Bob") == true, "expected source push snapshot to send")

    local encodedParts = {}
    for i = 1, #snapshotMessages do
        local fields = {}
        for field in snapshotMessages[i].payload:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        encodedParts[tonumber(fields[6]) or i] = fields[8] or ""
    end

    local snapshotPayload = source.addon.Base64.Decode(table.concat(encodedParts, ""))
    assertTrue(type(snapshotPayload) == "string" and snapshotPayload ~= "", "expected decoded snapshot payload")

    local lootLooter = nil
    for line in snapshotPayload:gmatch("[^\n]+") do
        local fields = {}
        for field in line:gmatch("[^\t]+") do
            fields[#fields + 1] = field
        end
        if fields[1] == "L" then
            lootLooter = source.addon.Base64.Decode(fields[10] or "")
            break
        end
    end

    assertEqual(lootLooter, "1", "expected DBSyncer to use the current query facade")
end)

test("db syncer records sync payload byte chunk metrics", function()
    local source = newHarness()
    source.addon.State.perfEnabled = true
    source.addon.hasPerf = true
    local itemLink = source.registerItem(9001, "Sync Blade")
    local itemString = source.addon.Item.GetItemStringFromLink(itemLink)
    source:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 77,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            realm = "TestRealm",
            startTime = 1000,
            players = {
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 2, class = "MAGE", join = 1000, countMS = 3 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", mode = "n", difficulty = 4, time = 1010, hash = "patchwerk-1010", players = { 1 } },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9001,
                    itemName = "Sync Blade",
                    itemString = itemString,
                    itemLink = itemLink,
                    itemRarity = 4,
                    itemTexture = "Icon9001",
                    itemCount = 1,
                    looterNid = 1,
                    rollType = source.rollTypes.MAINSPEC,
                    rollValue = 98,
                    bossNid = 10,
                    time = 1015,
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 102,
        },
    })

    local snapshotMessages = {}
    source.addon.IsInGroup = function()
        return true
    end
    source.addon.IsInRaid = function()
        return false
    end
    source.addon.Strings.TrimText = function(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    _G.SendAddonMessage = function(prefix, payload, channel, target)
        snapshotMessages[#snapshotMessages + 1] = {
            prefix = prefix,
            payload = payload,
            channel = channel,
            target = target,
        }
    end

    source:load("!KRT/Modules/Comms.lua")
    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Database/DBSyncer.lua")

    assertTrue(source.addon.DB.Syncer:BroadcastLoggerPush(77, "Bob") == true, "expected source push snapshot to send")
    assertTrue(#snapshotMessages > 1, "expected source snapshot to be chunked")

    local outgoing = source.addon.DB.Syncer:GetSyncMetrics()
    assertEqual(outgoing.outgoingSnapshots, 1, "expected one outgoing snapshot metric")
    assertEqual(outgoing.outgoingMessages, #snapshotMessages, "expected outgoing message frequency to match sent chunks")
    assertEqual(outgoing.outgoingChunks, #snapshotMessages, "expected outgoing chunk metric to match sent chunks")
    assertTrue(outgoing.outgoingBytes > 0, "expected outgoing byte metric")
    assertEqual(#outgoing.modes, 1, "expected one per-mode metrics row")
    assertEqual(outgoing.modes[1].mode, "PUSH", "expected outgoing metrics to be grouped by mode")
    assertEqual(outgoing.modes[1].outgoingChunks, #snapshotMessages, "expected per-mode outgoing chunks")

    local target = newHarness()
    target.addon.State.perfEnabled = true
    target.addon.hasPerf = true
    target:installRaidStore({})
    target.addon.IsInGroup = function()
        return true
    end
    target.addon.IsInRaid = function()
        return false
    end
    target:load("!KRT/Modules/Comms.lua")
    target:load("!KRT/Modules/Base64.lua")
    target:load("!KRT/Database/DBSyncer.lua")

    for i = 1, #snapshotMessages do
        local msg = snapshotMessages[i]
        target.addon.DB.Syncer:OnAddonMessage(msg.prefix, msg.payload, msg.channel, "Alice")
    end

    local incoming = target.addon.DB.Syncer:GetSyncMetrics()
    assertEqual(incoming.incomingSnapshots, 1, "expected one completed incoming snapshot metric")
    assertEqual(incoming.incomingMessages, #snapshotMessages, "expected incoming message frequency to match received chunks")
    assertEqual(incoming.incomingChunks, #snapshotMessages, "expected incoming chunk metric to match received chunks")
    assertTrue(incoming.incomingBytes > 0, "expected incoming byte metric")

    target.addon.DB.Syncer:ResetSyncMetrics()
    local reset = target.addon.DB.Syncer:GetSyncMetrics()
    assertEqual(reset.incomingMessages, 0, "expected reset to clear incoming metrics")
    assertEqual(#reset.modes, 0, "expected reset to clear per-mode metrics")
end)

test("logger export escapes loot CSV fields and filters by boss and player", function()
    local h, raid, Export = setupLoggerExportHarness({
        {
            schemaVersion = 1,
            raidNid = 42,
            zone = "Icecrown Citadel",
            size = 25,
            difficulty = 4,
            startTime = 1700000000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", join = 1700000000, leave = 1700000300 },
                { playerNid = 2, name = "Bob", class = "WARRIOR", join = 1700000000, leave = 1700000300 },
            },
            bossKills = {
                { bossNid = 10, name = "Queen, Lana'thel", time = 1700000100, difficulty = 4, players = { 1, 2 } },
                { bossNid = 11, name = "Sindragosa", time = 1700000200, difficulty = 4, players = { 2 } },
            },
            loot = {
                {
                    lootNid = 101,
                    bossNid = 10,
                    itemId = 9001,
                    itemName = 'Blade, "Queen"\nHero',
                    looterNid = 1,
                    rollType = 1,
                    rollValue = 99,
                    time = 1700000110,
                },
                {
                    lootNid = 102,
                    bossNid = 11,
                    itemId = 9002,
                    itemName = "Frost Ring",
                    looterNid = 2,
                    rollType = 2,
                    rollValue = 12,
                    time = 1700000210,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 12,
            nextLootNid = 103,
        },
    })

    local csv = Export:GetLootCSV(raid, { selectedBossNid = 10, selectedPlayerNid = 1 })
    assertTextContains(csv, "raidNid,raidDate,zone,size,difficulty,bossNid,boss,bossTime,lootNid,itemId,itemName,winner,class,rollType,rollValue,lootTime")
    assertTextContains(csv, "42," .. date("%Y-%m-%d %H:%M:%S", 1700000000) .. ",Icecrown Citadel,25,4,10")
    assertTextContains(csv, '"Queen, Lana\'thel"')
    assertTextContains(csv, '"Blade, ""Queen""\nHero"')
    assertTextContains(csv, ",Alice,MAGE,1,99,")
    assertTextNotContains(csv, "Frost Ring", "expected boss/player filter to exclude second loot row")
end)

test("logger export builds raid attendance CSV from attendance summaries", function()
    local _, raid, Export = setupLoggerExportHarness({
        {
            schemaVersion = 1,
            raidNid = 43,
            zone = "Naxxramas",
            size = 10,
            difficulty = 1,
            startTime = 1700001000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", join = 1700001000, leave = 1700001120 },
            },
            attendance = {
                {
                    playerNid = 1,
                    segments = {
                        { startTime = 1700001000, endTime = 1700001060 },
                        { startTime = 1700001060, endTime = 1700001120, online = false, subgroup = 2 },
                    },
                },
            },
            bossKills = {},
            loot = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })

    local csv = Export:GetRaidAttendanceCSV(raid)
    assertTextContains(csv, "raidNid,raidDate,zone,size,difficulty,playerNid,player,class,join,leave,attendanceSeconds,onlineSeconds,offlineSeconds,segmentCount")
    assertTextContains(csv, "43," .. date("%Y-%m-%d %H:%M:%S", 1700001000) .. ",Naxxramas,10,1,1,Alice,MAGE")
    assertTextContains(csv, ",120,60,60,2")
end)

test("raid query facade filters logger history with runtime indexes", function()
    local h = newHarness()
    h.feature.Sort.GetLootSortName = function(itemName, itemLink, itemId)
        return tostring(itemName or itemLink or itemId or "")
    end

    local lootRows = {}
    local expectedBoss20Bob = 0
    for i = 1, 90 do
        local bossNid = (i % 3 == 0) and 20 or 10
        local looterNid = ((i - 1) % 3) + 1
        lootRows[#lootRows + 1] = {
            lootNid = 1000 + i,
            bossNid = bossNid,
            itemId = 9000 + i,
            itemName = "Indexed Loot " .. tostring(i),
            looterNid = looterNid,
            rollType = 1,
            rollValue = i,
            time = 1700000000 + i,
        }
        if bossNid == 20 and looterNid == 2 then
            expectedBoss20Bob = expectedBoss20Bob + 1
        end
    end

    local store = h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 55,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700000000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", join = 1700000000 },
                { playerNid = 2, name = "Bob", class = "WARRIOR", join = 1700000000 },
                { playerNid = 3, name = "Cara", class = "PRIEST", join = 1700000000 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", mode = "n", time = 1700000100, players = { 1, 2, 3 } },
                { bossNid = 20, name = "Grobbulus", mode = "h", time = 1700000200, players = { 2, 3 } },
            },
            loot = lootRows,
            attendance = {
                { playerNid = 2, segments = { { startTime = 1700000000, endTime = 1700000120 } } },
                { playerNid = 3, segments = { { startTime = 1700000000, endTime = 1700000180, online = false } } },
            },
            nextPlayerNid = 4,
            nextBossNid = 21,
            nextLootNid = 1091,
        },
    })
    h:load("!KRT/Database/DBRaidQueries.lua")
    local queries = h.addon.DB.RaidQueries
    local raid = h.Database.EnsureRaidById(1)

    local runtime = store:EnsureRaidRuntime(raid)
    assertTrue(runtime.lootIdxByBossNid[20] ~= nil, "expected runtime boss loot index to be available")
    assertTrue(runtime.lootIdxByLooterNid[2] ~= nil, "expected runtime looter loot index to be available")

    local bossAttendees = queries:GetBossAttendance(raid, 20)
    assertEqual(#bossAttendees, 2, "expected boss attendance query to return indexed attendees")
    assertEqual(bossAttendees[1].name, "Bob", "expected boss attendance to preserve raid player order")
    assertEqual(bossAttendees[2].name, "Cara", "expected boss attendance to include second attendee")

    local attendance = queries:GetRaidAttendance(raid)
    assertEqual(#attendance, 3, "expected raid attendance query to include all players")
    assertEqual(attendance[2].attendanceSeconds, 120, "expected indexed attendance row for Bob")
    assertEqual(attendance[3].offlineSeconds, 180, "expected indexed attendance row for Cara")

    local filteredLoot = queries:GetLoot(raid, 20, "Bob")
    assertEqual(#filteredLoot, expectedBoss20Bob, "expected boss/player loot filters to agree with generated dataset")
    for i = 1, #filteredLoot do
        assertEqual(filteredLoot[i].bossNid, 20, "expected filtered loot boss nid")
        assertEqual(filteredLoot[i].looter, "Bob", "expected filtered loot looter")
    end
end)

test("raid query facade reuses provided output row buffers", function()
    local h = newHarness()
    h.feature.Sort.GetLootSortName = function(itemName, itemLink, itemId)
        return tostring(itemName or itemLink or itemId or "")
    end

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 56,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700000000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", join = 1700000000 },
                { playerNid = 2, name = "Bob", class = "WARRIOR", join = 1700000000 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", mode = "n", time = 1700000100, players = { 1, 2 } },
                { bossNid = 20, name = "Grobbulus", mode = "h", time = 1700000200, players = { 2 } },
            },
            loot = {
                {
                    lootNid = 1001,
                    bossNid = 10,
                    itemId = 9001,
                    itemName = "Reusable Blade",
                    looterNid = 1,
                    rollType = 1,
                    rollValue = 99,
                    time = 1700000110,
                },
                {
                    lootNid = 1002,
                    bossNid = 20,
                    itemId = 9002,
                    itemName = "Filtered Wand",
                    looterNid = 2,
                    rollType = 2,
                    rollValue = 88,
                    time = 1700000210,
                },
            },
            attendance = {
                { playerNid = 1, segments = { { startTime = 1700000000, endTime = 1700000120 } } },
            },
            nextPlayerNid = 3,
            nextBossNid = 21,
            nextLootNid = 1003,
        },
    })
    h:load("!KRT/Database/DBRaidQueries.lua")
    local queries = h.addon.DB.RaidQueries
    local raid = h.Database.EnsureRaidById(1)
    local out = {
        { stale = true },
        { stale = true },
        { stale = true },
    }
    local firstRow = out[1]
    local secondRow = out[2]

    queries:GetBossKills(raid, out)
    assertTrue(out[1] == firstRow, "expected boss query to reuse the first output row")
    assertTrue(out[2] == secondRow, "expected boss query to reuse the second output row")
    assertEqual(out[1].stale, nil, "expected reused boss row to clear stale fields")
    assertEqual(out[3], nil, "expected boss query to clear stale tail rows")

    queries:GetRaidAttendance(raid, out)
    assertTrue(out[1] == firstRow, "expected raid attendance query to reuse output rows")
    assertEqual(out[1].seq, nil, "expected raid attendance row to clear boss-only fields")
    assertEqual(out[2].name, "Bob", "expected second attendance row to be repopulated")

    queries:GetBossAttendance(raid, 20, out)
    assertTrue(out[1] == firstRow, "expected boss attendance query to reuse output rows")
    assertEqual(#out, 1, "expected boss attendance query to clear stale rows when result shrinks")
    assertEqual(out[1].name, "Bob", "expected filtered boss attendee row")

    queries:GetLoot(raid, 10, "Alice", out)
    assertTrue(out[1] == firstRow, "expected loot query to reuse output rows")
    assertEqual(#out, 1, "expected loot query to clear stale rows when result shrinks")
    assertEqual(out[1].itemName, "Reusable Blade", "expected filtered loot row to be repopulated")
    assertEqual(out[1].class, nil, "expected loot row to clear attendance-only fields")
end)

test("logger export returns header-only CSV when no rows match", function()
    local _, raid, Export = setupLoggerExportHarness({
        {
            schemaVersion = 1,
            raidNid = 45,
            zone = "Trial of the Crusader",
            size = 10,
            difficulty = 3,
            startTime = 1700003000,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })

    assertEqual(
        Export:GetLootCSV(raid, {}),
        "raidNid,raidDate,zone,size,difficulty,bossNid,boss,bossTime,lootNid,itemId,itemName,winner,class,rollType,rollValue,lootTime",
        "expected empty loot export to keep the CSV header"
    )
    assertEqual(
        Export:GetRaidAttendanceCSV(raid, {}),
        "raidNid,raidDate,zone,size,difficulty,playerNid,player,class,join,leave,attendanceSeconds,onlineSeconds,offlineSeconds,segmentCount",
        "expected empty raid-attendance export to keep the CSV header"
    )
end)

test("logger export writes shared loot sources as compact labels", function()
    local _, raid, Export = setupLoggerExportHarness({
        {
            schemaVersion = 6,
            raidNid = 47,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700005000,
            players = {},
            bossKills = {
                {
                    bossNid = 13,
                    name = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                    sourceKind = "shared",
                    source = "LootSources",
                    time = 1700005100,
                },
            },
            loot = {
                {
                    lootNid = 101,
                    bossNid = 13,
                    itemId = 91732,
                    itemName = "Resolver Ambiguous Charm",
                    time = 1700005110,
                    lootSource = {
                        kind = "shared",
                        bossNid = 13,
                        sourceNpcId = 0,
                        sourceName = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                        sourceKey = "shared|naxxramas|boss|15953|grand widow faerlina|any;naxxramas|boss|15954|noth the plaguebringer|any",
                        candidates = {
                            { npcId = 15953, name = "Grand Widow Faerlina", kind = "boss", sourceKey = "naxxramas|boss|15953|grand widow faerlina|any" },
                            { npcId = 15954, name = "Noth the Plaguebringer", kind = "boss", sourceKey = "naxxramas|boss|15954|noth the plaguebringer|any" },
                        },
                    },
                },
            },
            nextPlayerNid = 1,
            nextBossNid = 14,
            nextLootNid = 102,
        },
    })

    local csv = Export:GetLootCSV(raid, {})

    assertTextContains(csv, ",13,Shared,", "expected shared export source to use the compact label")
    assertTextNotContains(csv, "Grand Widow Faerlina", "expected shared export to omit tooltip-only candidates")
    assertTextNotContains(csv, "Noth the Plaguebringer", "expected shared export to omit tooltip-only candidates")
end)

test("logger loot view exposes compact shared source label and candidates", function()
    local h = newHarness()
    h.feature.Sort.GetLootSortName = function(itemName, itemLink, itemId)
        return tostring(itemName or itemLink or itemId or "")
    end
    h:installRaidStore({
        {
            schemaVersion = 6,
            raidNid = 48,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {
                {
                    bossNid = 13,
                    name = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                    sourceKind = "shared",
                    source = "LootSources",
                },
            },
            loot = {
                {
                    lootNid = 101,
                    bossNid = 13,
                    itemId = 91732,
                    itemName = "Resolver Ambiguous Charm",
                    lootSource = {
                        kind = "shared",
                        bossNid = 13,
                        sourceNpcId = 0,
                        sourceName = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                        sourceKey = "shared|naxxramas|boss|15953|grand widow faerlina|any;naxxramas|boss|15954|noth the plaguebringer|any",
                        candidates = {
                            { npcId = 15953, name = "Grand Widow Faerlina", kind = "boss", sourceKey = "naxxramas|boss|15953|grand widow faerlina|any" },
                            { npcId = 15954, name = "Noth the Plaguebringer", kind = "boss", sourceKey = "naxxramas|boss|15954|noth the plaguebringer|any" },
                        },
                    },
                },
            },
            nextPlayerNid = 1,
            nextBossNid = 14,
            nextLootNid = 102,
        },
    })
    h:load("!KRT/Database/DBRaidQueries.lua")

    local raid = h.Database.EnsureRaidById(1)
    local rows = h.addon.DB.RaidQueries:GetLoot(raid)

    assertEqual(#rows, 1, "expected one loot row")
    assertEqual(rows[1].sourceName, "Shared", "expected logger row to display compact shared source label")
    assertEqual(rows[1].sourceKind, "shared", "expected logger row to expose shared source kind")
    assertTrue(type(rows[1].sourceCandidates) == "table", "expected logger row to expose shared source candidates")
    assertEqual(#rows[1].sourceCandidates, 2, "expected logger row to expose both possible source bosses")
    assertEqual(rows[1].sourceCandidates[1].name, "Grand Widow Faerlina", "expected first tooltip candidate")
    assertEqual(rows[1].sourceCandidates[1].sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected first tooltip candidate source key")
    assertEqual(rows[1].sourceCandidates[2].name, "Noth the Plaguebringer", "expected second tooltip candidate")
    assertEqual(rows[1].sourceCandidates[2].sourceKey, "naxxramas|boss|15954|noth the plaguebringer|any", "expected second tooltip candidate source key")
    assertTextContains(rows[1].sourceKey, "shared|", "expected logger row to expose source key for future tooltips")
end)

test("db query and logger view share loot source model for shared legacy source", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSourceCandidates.lua")
    h:load("!KRT/Database/DBRaidQueries.lua")
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")

    h:installRaidStore({
        {
            schemaVersion = 6,
            raidNid = 48,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {
                {
                    bossNid = 13,
                    name = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                    sourceKind = "shared",
                    source = "LootSources",
                },
            },
            loot = {
                {
                    lootNid = 101,
                    bossNid = 13,
                    itemId = 91732,
                    itemName = "Resolver Ambiguous Charm",
                    looterNid = 1,
                    rollType = 1,
                    rollValue = 88,
                    lootSource = {
                        kind = "shared",
                        bossNid = 13,
                        sourceNpcId = 0,
                        sourceName = "Shared: Grand Widow Faerlina / Noth the Plaguebringer",
                        sourceKey = "shared|naxxramas|boss|15953|grand widow faerlina|any;naxxramas|boss|15954|noth the plaguebringer|any",
                        candidates = {
                            { npcId = 15953, name = "Grand Widow Faerlina", kind = "boss", sourceKey = "naxxramas|boss|15953|grand widow faerlina|any" },
                            { npcId = 15954, name = "Noth the Plaguebringer", kind = "boss", sourceKey = "naxxramas|boss|15954|noth the plaguebringer|any" },
                        },
                    },
                },
            },
            nextPlayerNid = 1,
            nextBossNid = 14,
            nextLootNid = 102,
        },
    })

    local raid = h.Database.EnsureRaidById(1)
    local queryRows = h.addon.DB.RaidQueries:GetLoot(raid)
    local viewRows = {}
    h.addon.Services.Logger.View:FillLootList(viewRows, raid, nil, nil)

    assertEqual(#queryRows, 1, "expected one DB query row")
    assertEqual(#viewRows, 1, "expected one logger view row")
    assertEqual(queryRows[1].sourceName, "Shared", "expected shared query source label")
    assertEqual(viewRows[1].sourceName, queryRows[1].sourceName, "expected logger view sourceName to match DB sourceName")
    assertEqual(viewRows[1].sourceKind, queryRows[1].sourceKind, "expected logger view sourceKind to match DB sourceKind")
    assertEqual(viewRows[1].sourceKey, queryRows[1].sourceKey, "expected logger view sourceKey to match DB sourceKey")
    assertTextContains(viewRows[1].sourceKind, "shared", "expected shared source kind")
    assertTextContains(queryRows[1].sourceKind, "shared", "expected shared source kind")
    assertTrue(type(viewRows[1].sourceCandidates) == "table", "expected logger view shared candidates")
    assertTrue(type(queryRows[1].sourceCandidates) == "table", "expected DB query shared candidates")
    assertEqual(#viewRows[1].sourceCandidates, 2, "expected logger view shared candidates")
    assertEqual(viewRows[1].sourceCandidates[1].name, queryRows[1].sourceCandidates[1].name, "expected shared candidate names to match")
    assertEqual(viewRows[1].sourceCandidates[2].sourceKey, queryRows[1].sourceCandidates[2].sourceKey, "expected shared source key to be preserved")
    assertEqual(viewRows[1].sourceCandidates[1].sourceKey, queryRows[1].sourceCandidates[1].sourceKey, "expected candidate source keys to match")
    assertEqual(viewRows[1].sourceCandidates[2].sourceKey, queryRows[1].sourceCandidates[2].sourceKey, "expected candidate source keys to match")
end)

test("logger loot XML exposes layout-only source column hitbox", function()
    local xml = readText("!KRT/UI/LootHistory.xml")

    assertTextContains(xml, 'name="$parentSourceHitBox"', "expected loot row XML to expose a source-column hitbox")
    assertTextNotContains(xml, "<Scripts>", "Logger XML must stay layout-only")
    assertTextNotContains(xml, "<OnEnter", "Logger XML must not bind tooltip handlers inline")
    assertTextNotContains(xml, "<OnLeave", "Logger XML must not bind tooltip handlers inline")
end)

test("logger view lists only bosses attended by selected raid player", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 46,
            zone = "Naxxramas",
            size = 25,
            difficulty = 2,
            startTime = 1700004000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE" },
                { playerNid = 2, name = "Bob", class = "WARRIOR" },
            },
            bossKills = {
                { bossNid = 10, name = "Anub'Rekhan", time = 1700004100, mode = "n", players = { 1, 2 } },
                { bossNid = 11, name = "Grand Widow Faerlina", time = 1700004200, mode = "h", players = { 2 } },
                { bossNid = 12, name = "Maexxna", time = 1700004300, mode = "n", players = { 1 } },
                {
                    bossNid = 13,
                    name = "Shared: Gothik the Harvester / Four Horsemen",
                    time = 1700004400,
                    mode = "n",
                    sourceKind = "shared",
                    players = { 1 },
                },
            },
            loot = {},
            nextPlayerNid = 3,
            nextBossNid = 14,
            nextLootNid = 1,
        },
    })
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")

    local raid = h.Database.EnsureRaidById(1)
    local rows = {}
    h.addon.Services.Logger.View:GetPlayerBossParticipationList(rows, raid, 1)

    assertEqual(#rows, 2, "expected only bosses attended by Alice")
    assertEqual(rows[1].id, 10, "expected first attended boss nid")
    assertEqual(rows[1].name, "Anub'Rekhan", "expected first attended boss name")
    assertEqual(rows[1].mode, "N", "expected normal mode label")
    assertEqual(rows[2].id, 12, "expected second attended boss nid")
    assertEqual(rows[2].name, "Maexxna", "expected second attended boss name")
    assertTextNotContains(rows[2].name, "Shared:", "expected shared loot source records to stay out of boss participation")
end)

test("logger view and export hot paths record perf measurements", function()
    local h, raid, Export = setupLoggerExportHarness({
        {
            schemaVersion = 1,
            raidNid = 49,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700006000,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE", join = 1700006000, leave = 1700006120 },
                { playerNid = 2, name = "Bob", class = "WARRIOR", join = 1700006000, leave = 1700006120 },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", time = 1700006060, mode = "n", players = { 1, 2 } },
            },
            loot = {
                {
                    lootNid = 101,
                    bossNid = 10,
                    itemId = 9101,
                    itemName = "Measured Blade",
                    looterNid = 1,
                    rollType = 1,
                    rollValue = 88,
                    time = 1700006070,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 11,
            nextLootNid = 102,
        },
    })
    h:load("!KRT/Services/Logger/View.lua")

    local perfRows = {}
    h.addon.hasPerf = true
    h.addon._PerfStart = function()
        return #perfRows + 1
    end
    h.addon._PerfFinish = function(_, label, startedAt, details)
        perfRows[#perfRows + 1] = {
            label = label,
            startedAt = startedAt,
            details = details,
        }
    end

    local View = h.addon.Services.Logger.View
    local rows = {}
    View:FillLootList(rows, raid, 10, "Alice")
    View:FillBossList(rows, raid)
    View:FillRaidAttendeesList(rows, raid)
    View:FillBossAttendeesList(rows, raid, 10)
    View:GetPlayerBossParticipationList(rows, raid, 1)
    Export:GetLootCSV(raid, { selectedBossNid = 10, selectedPlayerNid = 1 })
    Export:GetRaidAttendanceCSV(raid)

    local function findPerf(label)
        for i = 1, #perfRows do
            if perfRows[i].label == label then
                return perfRows[i]
            end
        end
        return nil
    end

    local function assertPerf(label, detail)
        local row = findPerf(label)
        assertTrue(row ~= nil, "expected " .. label .. " perf measurement")
        assertTextContains(row.details, "raid=49", "expected raid context for " .. label)
        assertTextContains(row.details, detail, "expected row context for " .. label)
    end

    assertPerf("Logger.View.FillLootList", "rows=1")
    assertPerf("Logger.View.FillBossList", "rows=1")
    assertPerf("Logger.View.FillRaidAttendeesList", "rows=2")
    assertPerf("Logger.View.FillBossAttendeesList", "rows=2")
    assertPerf("Logger.View.GetPlayerBossParticipationList", "rows=1")
    assertPerf("Logger.Export.GetLootCSV", "rows=1")
    assertPerf("Logger.Export.GetRaidAttendanceCSV", "rows=2")
end)

test("logger updates duplicate item entries by lootNid only", function()
    local h = newHarness()
    local link = h.registerItem(9001, "Twinblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", countMS = 0 },
                { playerNid = 2, name = "Bob", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Patchwerk" },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9001,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 80,
                    bossNid = 10,
                },
                {
                    lootNid = 102,
                    itemId = 9001,
                    itemLink = link,
                    looterNid = 2,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 90,
                    bossNid = 10,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 11,
            nextLootNid = 103,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")
    h:load("!KRT/Controllers/Logger.lua")

    local raid = h.Database.EnsureRaidById(1)

    local request = {
        lootNid = 102,
        looter = "Alice",
        rollType = h.rollTypes.OFFSPEC,
        rollValue = 22,
        source = "TEST_DUPLICATE",
        raidId = 1,
    }
    h.Bus.TriggerEvent(h.addon.Events.Internal.LoggerLootLogRequest, request)
    local ok = request.ok
    assertTrue(ok == true, "expected loot log update to succeed")
    assertEqual(raid.loot[1].looterNid, 1, "expected first duplicate entry to remain untouched")
    assertEqual(raid.loot[1].rollValue, 80, "expected first duplicate roll to remain untouched")
    assertEqual(raid.loot[2].looterNid, 1, "expected second duplicate entry to be updated")
    assertEqual(raid.loot[2].rollType, h.rollTypes.OFFSPEC, "expected second duplicate roll type to update")
    assertEqual(raid.loot[2].rollValue, 22, "expected second duplicate roll value to update")

    h.logs.error = {}
    request = {
        lootNid = 9001,
        looter = "Bob",
        rollType = h.rollTypes.FREE,
        rollValue = 1,
        source = "TEST_RAW_ITEM_ID",
        raidId = 1,
    }
    h.Bus.TriggerEvent(h.addon.Events.Internal.LoggerLootLogRequest, request)
    local bad = request.ok
    assertTrue(bad == false, "expected raw itemId logger update to fail")
    assertContains(h.logs.error, "expected lootNid but got raw itemId", "expected explicit raw itemId guard-rail log")
end)

test("logger loot refresh coalesces duplicate raid update bursts", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")
    h:load("!KRT/Controllers/Logger.lua")

    local Logger = h.addon.Controllers.Logger
    Logger._SetSelectedRaid(1)
    Logger._lootUiHandle = nil

    local scheduledCount = 0
    local cancelledCount = 0
    local oldScheduleTimer = Logger.ScheduleTimer
    local oldCancelTimer = Logger.CancelTimer
    Logger.ScheduleTimer = function(self, callback, delay, ...)
        scheduledCount = scheduledCount + 1
        return oldScheduleTimer(self, callback, delay, ...)
    end
    Logger.CancelTimer = function(self, handle)
        cancelledCount = cancelledCount + 1
        return oldCancelTimer(self, handle)
    end

    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidLootUpdate, 2)
    assertEqual(scheduledCount, 0, "expected unrelated raid loot updates to skip logger loot refresh")

    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidLootUpdate, 1)
    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidLootUpdate, 1)

    assertEqual(scheduledCount, 1, "expected duplicate raid loot updates to reuse one pending refresh")
    assertEqual(cancelledCount, 0, "expected duplicate raid loot updates to avoid cancelling the pending refresh")
    h.flushTimers()
    assertEqual(Logger.Loot._ctrl.dirtyCount, 1, "expected coalesced logger loot refresh to dirty the list once")
    assertEqual(Logger._lootUiHandle, nil, "expected logger loot refresh handle to clear after firing")
end)

test("logger actions resolve edit winner against boss attendees", function()
    local h = newHarness()
    local link = h.registerItem(9002, "Attendee Blade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE" },
                { playerNid = 2, name = "Bob", class = "WARRIOR" },
            },
            bossKills = {
                { bossNid = 10, name = "Patchwerk", players = { 2 } },
            },
            loot = {
                {
                    lootNid = 101,
                    itemId = 9002,
                    itemLink = link,
                    bossNid = 10,
                },
            },
            nextPlayerNid = 3,
            nextBossNid = 11,
            nextLootNid = 102,
        },
    })
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local winner = Actions:ResolveLootEditWinner(1, 101, " bob ")

    assertEqual(winner, "Bob", "expected editor winner resolution to use boss attendees")
end)

test("logger maintenance deletes empty raids and purges history", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 10,
            zone = "Empty One",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 20,
            zone = "Naxxramas",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 30,
            zone = "Empty Two",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 2
    h.addon.State.lastBoss = 99
    h.Database.SetCurrentRaid = function(raidId)
        h.addon.State.currentRaid = raidId
        return raidId
    end
    h.Database.GetRaidNidById = function(raidId)
        local raid = h.store:GetRaidByIndex(raidId)
        return raid and raid.raidNid or nil
    end
    h.Database.GetRaidIdByNid = function(raidNid)
        return h.store:GetRaidIndexByNid(raidNid)
    end

    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local removedEmpty = Actions:DeleteEmptyRaids()

    assertEqual(removedEmpty.removed, 2, "expected empty raid maintenance to delete two empty raids")
    assertEqual(#_G.KRT_Raids, 1, "expected populated raid to remain after deleting empty raids")
    assertEqual(_G.KRT_Raids[1].raidNid, 20, "expected populated raid nid to remain stable")
    assertEqual(h.Database.GetCurrentRaid(), 1, "expected current raid index to follow the remaining current raid nid")

    local purged = Actions:PurgeRaidHistory()

    assertEqual(purged.removed, 1, "expected purge to remove remaining history")
    assertEqual(#_G.KRT_Raids, 0, "expected purge to clear all raid logs")
    assertEqual(h.Database.GetCurrentRaid(), nil, "expected purge to clear current raid selection")
    assertEqual(h.Database.GetLastBoss(), nil, "expected purge to clear last boss selection")
end)

test("logger maintenance clean up removes selected low value history", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 10,
            zone = "Empty Raid",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 20,
            zone = "Naxxramas",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 11, name = "Anub'Rekhan", time = 1000 },
            },
            loot = {
                { lootNid = 1, itemName = "Epic Loot", itemRarity = 4, bossNid = 11, time = 1010 },
                { lootNid = 2, itemName = "Rare Loot", itemRarity = 3, bossNid = 11, time = 1020 },
                {
                    lootNid = 3,
                    itemName = "Legendary Loot",
                    itemLink = "|cffff8000|Hitem:90003:0:0:0:0:0:0:0|h[Legendary Loot]|h|r",
                    bossNid = 11,
                    time = 1030,
                },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 12,
            nextLootNid = 4,
        },
        {
            schemaVersion = 1,
            raidNid = 30,
            zone = "No Boss",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {},
            loot = {
                { lootNid = 1, itemName = "Bossless Epic", itemRarity = 4, time = 1010 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 2,
        },
    })
    h.addon.State.currentRaid = 2
    h.Database.SetCurrentRaid = function(raidId)
        h.addon.State.currentRaid = raidId
        return raidId
    end
    h.Database.GetRaidNidById = function(raidId)
        local raid = h.store:GetRaidByIndex(raidId)
        return raid and raid.raidNid or nil
    end
    h.Database.GetRaidIdByNid = function(raidNid)
        return h.store:GetRaidIndexByNid(raidNid)
    end

    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local preview = Actions:GetRaidHistoryScan()

    assertEqual(preview.emptyRaids, 1, "expected cleanup preview to count empty raids")
    assertEqual(preview.nonEpicLoot, 1, "expected cleanup preview to count non-epic loot")
    assertEqual(preview.raidsWithoutBosses, 1, "expected cleanup preview to count non-empty raids without boss encounters")

    local result = Actions:RemoveRaidHistoryEntries({
        emptyRaids = true,
        nonEpicLoot = true,
        noBossEncounter = true,
    })

    assertEqual(result.emptyRaids, 1, "expected cleanup to remove the empty raid")
    assertEqual(result.noBossEncounter, 1, "expected cleanup to remove the raid without boss encounters")
    assertEqual(result.nonEpicLoot, 1, "expected cleanup to remove one non-epic loot row")
    assertEqual(result.raidsRemoved, 2, "expected cleanup to report removed raid logs")
    assertEqual(result.lootRemoved, 1, "expected cleanup to report removed loot rows")
    assertEqual(#_G.KRT_Raids, 1, "expected only the raid with boss encounters to remain")
    assertEqual(#_G.KRT_Raids[1].loot, 2, "expected only epic-or-better loot rows to remain")
    assertEqual(_G.KRT_Raids[1].loot[1].itemName, "Epic Loot", "expected epic loot to remain")
    assertEqual(_G.KRT_Raids[1].loot[2].itemName, "Legendary Loot", "expected legendary loot to remain")
    assertEqual(h.Database.GetCurrentRaid(), 1, "expected current raid index to follow the remaining raid nid")
end)

test("logger maintenance no boss cleanup does not delete empty raids unless selected", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 10,
            zone = "Empty Raid",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 20,
            zone = "No Boss",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {},
            loot = {
                { lootNid = 1, itemName = "Bossless Epic", itemRarity = 4, time = 1010 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 2,
        },
    })
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local result = h.addon.Services.Logger.Actions:RemoveRaidHistoryEntries({
        noBossEncounter = true,
    })

    assertEqual(result.emptyRaids, 0, "expected no-boss cleanup not to count empty raids")
    assertEqual(result.noBossEncounter, 1, "expected no-boss cleanup to remove one non-empty no-boss raid")
    assertEqual(#_G.KRT_Raids, 1, "expected the empty raid to remain when Empty Raid is not selected")
    assertEqual(_G.KRT_Raids[1].raidNid, 10, "expected the remaining raid to be the empty raid")
end)

test("logger maintenance cleanup removes selected history in chunks", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 10,
            zone = "Empty Raid",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 20,
            zone = "Cleanup Raid",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 1, name = "Boss", time = 1000 },
            },
            loot = {
                { lootNid = 1, itemName = "Green Loot", itemRarity = 2, time = 1001 },
                { lootNid = 2, itemName = "Epic Loot", itemRarity = 4, time = 1002 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 2,
            nextLootNid = 3,
        },
        {
            schemaVersion = 1,
            raidNid = 30,
            zone = "No Boss",
            players = {
                { playerNid = 1, name = "Bob" },
            },
            bossKills = {},
            loot = {
                { lootNid = 1, itemName = "Bossless Epic", itemRarity = 4, time = 1010 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 2,
        },
    })
    h.addon.State.currentRaid = 2
    h.Database.SetCurrentRaid = function(raidId)
        h.addon.State.currentRaid = raidId
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local completed
    local callbackCount = 0
    local handle = Actions:RequestRemoveRaidHistoryEntries(function(result, ok)
        callbackCount = callbackCount + 1
        assertTrue(ok == true, "expected chunked cleanup callback to report success")
        completed = result
    end, {
        emptyRaids = true,
        nonEpicLoot = true,
        noBossEncounter = true,
        chunkSize = 1,
        delaySeconds = 0,
    })

    assertEqual(h.timerCount(), 1, "expected chunked cleanup to schedule work instead of completing inline")
    assertEqual(callbackCount, 0, "expected chunked cleanup callback to wait for scheduled chunks")

    local guard = 0
    while h.timerCount() > 0 and guard < 20 do
        h:flushTimers()
        guard = guard + 1
    end

    assertEqual(callbackCount, 1, "expected chunked cleanup callback to run once")
    assertTrue(handle:IsCancelled() == true, "expected completed chunked cleanup handle to become inactive")
    assertEqual(completed.emptyRaids, 1, "expected cleanup to remove the empty raid")
    assertEqual(completed.noBossEncounter, 1, "expected cleanup to remove the raid without boss encounters")
    assertEqual(completed.nonEpicLoot, 1, "expected cleanup to remove one non-epic loot row")
    assertEqual(completed.raidsRemoved, 2, "expected cleanup to report removed raid logs")
    assertEqual(completed.lootRemoved, 1, "expected cleanup to report removed loot rows")
    assertEqual(#_G.KRT_Raids, 1, "expected only the raid with boss encounters to remain")
    assertEqual(_G.KRT_Raids[1].raidNid, 20, "expected the cleanup raid to remain")
    assertEqual(#_G.KRT_Raids[1].loot, 1, "expected only epic-or-better loot rows to remain")
    assertEqual(_G.KRT_Raids[1].loot[1].itemName, "Epic Loot", "expected epic loot to remain")
    assertEqual(h.Database.GetCurrentRaid(), 1, "expected current raid index to follow the remaining raid nid")
end)

test("logger maintenance chunked cleanup finalizes cache when cancelled", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 10,
            zone = "Keep Raid",
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 1, name = "Boss", time = 1000 },
            },
            loot = {
                { lootNid = 1, itemName = "Epic Loot", itemRarity = 4, time = 1001 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 2,
            nextLootNid = 2,
        },
        {
            schemaVersion = 1,
            raidNid = 20,
            zone = "Remove Current Raid",
            players = {
                { playerNid = 1, name = "Bob" },
            },
            bossKills = {},
            loot = {
                { lootNid = 1, itemName = "Bossless Epic", itemRarity = 4, time = 1010 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 2,
        },
    })
    h.addon.State.currentRaid = 2
    h.Database.SetCurrentRaid = function(raidId)
        h.addon.State.currentRaid = raidId
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local callbackCount = 0
    local handle = Actions:RequestRemoveRaidHistoryEntries(function()
        callbackCount = callbackCount + 1
    end, {
        noBossEncounter = true,
        chunkSize = 1,
        delaySeconds = 0,
    })

    h:flushTimers()

    assertEqual(callbackCount, 0, "expected chunked cleanup callback not to run before completion")
    assertTrue(handle:Cancel() == true, "expected partial cleanup cancel to succeed")
    assertEqual(h.timerCount(), 0, "expected partial cleanup cancel to remove pending timer work")
    assertEqual(callbackCount, 0, "expected partial cleanup cancel not to call completion callback")
    assertEqual(#_G.KRT_Raids, 1, "expected partial cleanup mutation to be finalized")
    assertEqual(_G.KRT_Raids[1].raidNid, 10, "expected remaining raw raid list to be usable after cancel")
    assertEqual(h.Database.GetCurrentRaid(), nil, "expected removed current raid selection to be cleared on cancel")
end)

test("logger maintenance rebuilds missing loot sources from static source data", function()
    local h = newHarness()
    local link = h.registerItem(91730, "Resolver Boss Blade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {},
            loot = {
                {
                    lootNid = 101,
                    itemId = 91730,
                    itemLink = link,
                    itemName = "Resolver Boss Blade",
                    bossNid = 0,
                    time = 1100,
                },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 102,
        },
    })

    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [91730] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
            },
        },
    })
    h.feature.LootSources = h.addon.LootSources
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local result = Actions:EnsureLootSources()
    local raid = h.Database.EnsureRaidById(1)

    assertEqual(result.repaired, 1, "expected one loot row to be repaired")
    assertEqual(result.bossesCreated, 1, "expected source rebuild to create one static source record")
    assertEqual(#raid.bossKills, 1, "expected static source boss to be stored on the raid")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected static source boss name")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected missing loot source to bind to the rebuilt boss")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected rebuilt loot row to store provenance kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Grand Widow Faerlina", "expected rebuilt loot row to store provenance name")
    assertEqual(raid.loot[1].lootSource.sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected rebuilt loot row to store provenance source key")
    assertEqual(raid.bossKills[1].sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected rebuilt static source boss to store source key")
end)

test("logger maintenance rebuilds missing loot sources in chunks", function()
    local h = newHarness()
    local linkA = h.registerItem(91730, "Resolver Boss Blade")
    local linkB = h.registerItem(91731, "Resolver Noth Ring")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 201,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {},
            loot = {
                {
                    lootNid = 101,
                    itemId = 91730,
                    itemLink = linkA,
                    itemName = "Resolver Boss Blade",
                    bossNid = 0,
                    time = 1100,
                },
                {
                    lootNid = 102,
                    itemId = 91731,
                    itemLink = linkB,
                    itemName = "Resolver Noth Ring",
                    bossNid = 0,
                    time = 1110,
                },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 103,
        },
    })

    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [91730] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
            },
        },
        [91731] = {
            {
                npcId = 15954,
                npcName = "Noth the Plaguebringer",
                raid = "Naxxramas",
                kind = "boss",
            },
        },
    })
    h.feature.LootSources = h.addon.LootSources
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local completed
    local callbackCount = 0
    local handle = Actions:RequestEnsureLootSources(function(result, ok)
        callbackCount = callbackCount + 1
        assertTrue(ok == true, "expected chunked loot-source rebuild callback to report success")
        completed = result
    end, { chunkSize = 1, delaySeconds = 0 })

    assertEqual(h.timerCount(), 1, "expected chunked loot-source rebuild to schedule work instead of completing inline")
    assertEqual(callbackCount, 0, "expected chunked loot-source rebuild callback to wait for scheduled chunks")

    local guard = 0
    while h.timerCount() > 0 and guard < 20 do
        h:flushTimers()
        guard = guard + 1
    end

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(callbackCount, 1, "expected chunked loot-source rebuild callback to run once")
    assertTrue(handle:IsCancelled() == true, "expected completed chunked rebuild handle to become inactive")
    assertEqual(completed.raids, 1, "expected chunked rebuild to scan one raid")
    assertEqual(completed.scanned, 2, "expected chunked rebuild to scan both loot rows")
    assertEqual(completed.repaired, 2, "expected chunked rebuild to repair both loot rows")
    assertEqual(completed.bossesCreated, 2, "expected chunked rebuild to create source boss records")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected first loot row to bind to rebuilt source")
    assertEqual(raid.loot[2].lootSource.kind, "boss", "expected second source provenance to be rebuilt")
    assertEqual(raid.loot[2].lootSource.sourceName, "Noth the Plaguebringer", "expected second source display label")
end)

test("logger maintenance scans history report metrics", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 101,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {
                { playerNid = 1, name = "Alice" },
                { playerNid = 2, name = "alice" },
            },
            bossKills = {
                { bossNid = 11, name = "Anub'Rekhan", time = 1000 },
            },
            loot = {
                { lootNid = 1, itemId = 90001, itemName = "Valid Loot", bossNid = 11, looterNid = 1, time = 1010 },
                { lootNid = 2, itemId = 90002, itemName = "Missing Source", itemRarity = 3, bossNid = 0, time = 1020 },
                {
                    lootNid = 3,
                    itemId = 90003,
                    itemName = "Invalid Source",
                    bossNid = 999,
                    looterNid = 99,
                    time = 1030,
                },
            },
            attendance = {
                { playerNid = 88 },
            },
            changes = {},
            nextPlayerNid = 3,
            nextBossNid = 12,
            nextLootNid = 4,
        },
        {
            schemaVersion = 1,
            raidNid = 102,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 11, name = "Anub'Rekhan", time = 1015 },
            },
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 12,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 103,
            zone = "Empty",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    _G.KRT_Raids[1].loot[3].looterNid = 99
    _G.KRT_Raids[1].attendance = {
        { playerNid = 88 },
    }

    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local result = Actions:GetRaidHistoryScan()

    assertEqual(result.raids, 3, "expected scan to count all raids")
    assertEqual(result.emptyRaids, 1, "expected scan to count empty raids")
    assertEqual(result.raidsWithoutBosses, 0, "expected scan not to count empty raids as no-boss encounters")
    assertEqual(result.lootRows, 3, "expected scan to count loot rows")
    assertEqual(result.nonEpicLoot, 1, "expected scan to count non-epic loot")
    assertEqual(result.missingSources, 1, "expected scan to count loot rows without a source")
    assertEqual(result.invalidSources, 1, "expected scan to count loot rows pointing at missing bosses")
    assertEqual(result.orphanLoot, 1, "expected scan to count loot rows pointing at missing looters")
    assertEqual(result.orphanAttendance, 1, "expected scan to count attendance rows pointing at missing players")
    assertEqual(result.playerNameConflicts, 1, "expected scan to count case-only player-name conflicts")
    assertEqual(result.duplicateRaidCandidates, 1, "expected scan to count one nearby duplicate raid candidate")
end)

test("logger maintenance history scan can run in chunks", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 111,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700000000,
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 11, name = "Anub'Rekhan", time = 1700000060 },
            },
            loot = {
                { lootNid = 1, itemId = 90001, itemName = "Valid Loot", bossNid = 11, looterNid = 1, time = 1700000070 },
            },
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 12,
            nextLootNid = 2,
        },
        {
            schemaVersion = 1,
            raidNid = 112,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            startTime = 1700000120,
            players = {
                { playerNid = 1, name = "Alice" },
            },
            bossKills = {
                { bossNid = 11, name = "Anub'Rekhan", time = 1700000180 },
            },
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 2,
            nextBossNid = 12,
            nextLootNid = 1,
        },
        {
            schemaVersion = 1,
            raidNid = 113,
            zone = "Empty",
            players = {},
            bossKills = {},
            loot = {},
            attendance = {},
            changes = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })

    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")

    local Actions = h.addon.Services.Logger.Actions
    local expected = Actions:GetRaidHistoryScan()
    local completed
    local callbackCount = 0
    local handle = Actions:RequestRaidHistoryScan(function(result, ok)
        callbackCount = callbackCount + 1
        assertTrue(ok == true, "expected chunked scan callback to report success")
        completed = result
    end, { chunkSize = 1, delaySeconds = 0 })

    assertEqual(h.timerCount(), 1, "expected chunked history scan to schedule work instead of completing inline")
    assertEqual(callbackCount, 0, "expected chunked history scan callback to wait for scheduled chunks")

    local guard = 0
    while h.timerCount() > 0 and guard < 20 do
        h:flushTimers()
        guard = guard + 1
    end

    assertEqual(callbackCount, 1, "expected chunked history scan callback to run once")
    assertTrue(handle:IsCancelled() == true, "expected completed chunked scan handle to become inactive")
    assertEqual(completed.raids, expected.raids, "expected chunked scan raid count to match sync scan")
    assertEqual(completed.emptyRaids, expected.emptyRaids, "expected chunked scan empty raid count to match sync scan")
    assertEqual(completed.lootRows, expected.lootRows, "expected chunked scan loot count to match sync scan")
    assertEqual(completed.duplicateRaidCandidates, expected.duplicateRaidCandidates, "expected chunked scan duplicate count to match sync scan")
end)

test("spammer panel preview reads the saved LFM draft", function()
    local h = newHarness()
    _G.KRT_Spammer = {
        Name = "ICC 25",
        Duration = "60",
        Tank = "1",
        Healer = "5",
        Melee = "8",
        Ranged = "10",
        Message = "full clear",
    }

    h:load("!KRT/Services/Spammer/Draft.lua")
    h:load("!KRT/Controllers/Spammer.lua")

    local Spammer = h.addon.Controllers.Spammer
    local preview = Spammer:RequestPreview()

    assertEqual(_G.KRT_Spammer.Name, "ICC 25", "expected preview to leave saved raid name unchanged")
    assertEqual(_G.KRT_Spammer.Duration, "60", "expected preview to read saved duration")
    assertTextContains(preview.output, "LFM ICC 25", "expected preview to use saved raid name")
    assertTextContains(preview.output, "Need", "expected preview to include role needs")
    assertTrue(preview.length > 3, "expected preview to report message length")

    local cleared = Spammer:RequestClear()

    assertEqual(_G.KRT_Spammer.Name, nil, "expected clear to remove saved raid name")
    assertEqual(_G.KRT_Spammer.Message, nil, "expected clear to remove saved message")
    assertEqual(_G.KRT_Spammer.Duration, "60", "expected clear to restore default duration")
    assertEqual(cleared.output, "LFM", "expected clear to reset preview output")
    assertEqual(cleared.length, 3, "expected clear to report the default preview length")
end)

test("warnings panel templates add default raid warnings without duplicates", function()
    local h = newHarness()
    _G.KRT_Warnings = {}
    h.addon.UI.Scaffold.CreateListPanel = function()
        return {
            OnLoad = function(_, frame)
                return frame and frame.GetName and frame:GetName() or "KRTWarnings"
            end,
            Refresh = function() end,
        }
    end

    h:load("!KRT/Services/Warnings/Store.lua")
    h:load("!KRT/Controllers/Warnings.lua")

    local Warnings = h.addon.Controllers.Warnings
    local result = Warnings:RequestEnsureDefaultTemplates()
    local second = Warnings:RequestEnsureDefaultTemplates()
    local preview = Warnings:RequestTemplatePreview()

    assertEqual(result.added, 6, "expected missing default templates to be added")
    assertEqual(second.added, 0, "expected template install to be idempotent")
    assertEqual(#_G.KRT_Warnings, 6, "expected default warnings to be stored once")
    assertTextContains(preview.text, "Pull", "expected template preview to include existing pull template")
    assertTextContains(preview.text, "Stop DPS", "expected template preview to include default stop DPS template")
end)

test("warnings panel seeds stock templates for fresh saved variables", function()
    local h = newHarness()
    _G.KRT_Warnings = {}
    h.addon.State.warningsSavedVariablesFresh = true
    h.addon.UI.Scaffold.CreateListPanel = function()
        return {
            OnLoad = function(_, frame)
                return frame and frame.GetName and frame:GetName() or "KRTWarnings"
            end,
            Refresh = function() end,
        }
    end

    h:load("!KRT/Services/Warnings/Store.lua")
    h:load("!KRT/Controllers/Warnings.lua")

    assertEqual(#_G.KRT_Warnings, 6, "expected fresh saved variables to seed stock warning templates")
    assertEqual(h.addon.State.warningsSavedVariablesFresh, false, "expected fresh warning seed flag to be consumed")
end)

test("warnings panel clear saved warnings removes every saved message", function()
    local h = newHarness()
    _G.KRT_Warnings = {
        { name = "Pull", content = "Pull in 10 seconds." },
        { name = "Stack", content = "Stack on marker." },
    }
    h.addon.L.StrConfigRaidWarningPreviewEmpty = "No raid warnings configured."
    h.addon.UI.Scaffold.CreateListPanel = function()
        return {
            OnLoad = function(_, frame)
                return frame and frame.GetName and frame:GetName() or "KRTWarnings"
            end,
            Refresh = function() end,
        }
    end

    h:load("!KRT/Services/Warnings/Store.lua")
    h:load("!KRT/Controllers/Warnings.lua")

    local Warnings = h.addon.Controllers.Warnings
    local result = Warnings:RequestClearSavedWarnings()
    local preview = Warnings:RequestTemplatePreview()

    assertEqual(result.removed, 2, "expected clear saved warnings to report removed messages")
    assertEqual(result.total, 0, "expected clear saved warnings to report an empty store")
    assertEqual(#_G.KRT_Warnings, 0, "expected clear saved warnings to empty KRT_Warnings")
    assertTextContains(preview.text, "No raid warnings configured.", "expected preview to show the empty warning state")
end)

test("warnings panel clear saved warnings can keep stock templates", function()
    local h = newHarness()
    _G.KRT_Warnings = {}
    h.addon.UI.Scaffold.CreateListPanel = function()
        return {
            OnLoad = function(_, frame)
                return frame and frame.GetName and frame:GetName() or "KRTWarnings"
            end,
            Refresh = function() end,
        }
    end

    h:load("!KRT/Services/Warnings/Store.lua")
    h:load("!KRT/Controllers/Warnings.lua")

    local Warnings = h.addon.Controllers.Warnings
    Warnings:RequestEnsureDefaultTemplates()
    table.insert(_G.KRT_Warnings, { name = "Custom", content = "Custom warning." })

    local result = Warnings:RequestClearSavedWarnings(false)
    local preview = Warnings:RequestTemplatePreview()

    assertEqual(result.removed, 1, "expected clear saved warnings to report removed custom messages")
    assertEqual(result.total, 6, "expected stock templates to be restored when stock deletion is declined")
    assertEqual(#_G.KRT_Warnings, 6, "expected stock templates to remain after custom cleanup")
    assertTextContains(preview.text, "Pull", "expected restored stock templates to include Pull")
    assertTrue(preview.text:find("Custom", 1, true) == nil, "expected custom warnings to be removed")
end)

test("loot context helpers stay service-owned without Database backdoor", function()
    local h = newHarness()

    h:load("!KRT/Services/Loot.lua")

    assertTrue(type(h.addon.Services.Loot._Context) == "table", "expected service-owned loot context helpers")
    assertTrue(h.addon.Database._LootContext == nil, "expected no Database loot context backdoor")
end)

test("loot workflow shadow state records transitions and recent receipts", function()
    local h = newHarness()
    h:load("!KRT/Services/Loot/Workflow.lua")
    local Workflow = h.addon.Services.Loot._Workflow
    local ctx = {}

    Workflow.BeginLootWindow(ctx, {
        raidNum = 1,
        source = "LOOT_OPENED",
    })
    Workflow.SelectItem(ctx, {
        itemLink = "|cff0070dd|Hitem:92001::::::::|h[Workflow Blade]|h|r",
        itemKey = "item:92001",
    })
    Workflow.BeginRoll(ctx, {
        itemLink = "|cff0070dd|Hitem:92001::::::::|h[Workflow Blade]|h|r",
        rollType = h.rollTypes.MAINSPEC,
        sessionId = "ROLL:1",
        source = "lootWindow",
    })
    Workflow.QueueAward(ctx, {
        itemLink = "|cff0070dd|Hitem:92001::::::::|h[Workflow Blade]|h|r",
        playerName = "Tester",
        rollType = h.rollTypes.MAINSPEC,
        rollValue = 97,
        rollSessionId = "ROLL:1",
    })

    for i = 1, 22 do
        Workflow.RecordReceipt(ctx, {
            kind = "loot_received",
            msg = "receipt-" .. i,
            itemLink = "|cff0070dd|Hitem:" .. tostring(92000 + i) .. "::::::::|h[Workflow Loot]|h|r",
        })
    end

    local snapshot = Workflow.BuildSnapshot(ctx)
    assertEqual(snapshot.phase, "award_pending", "expected workflow to expose pending-award phase")
    assertEqual(snapshot.summaryText, "award_pending: Tester", "expected workflow to expose a compact current-step summary")
    assertEqual(#snapshot.steps, 7, "expected workflow snapshot to expose every Master Loot flow step")
    assertEqual(snapshot.steps[1].phase, "loot_window", "expected workflow steps to start at loot window")
    assertEqual(snapshot.steps[2].phase, "item_selected", "expected workflow steps to include item selection")
    assertEqual(snapshot.steps[3].phase, "rolling", "expected workflow steps to include rolling")
    assertEqual(snapshot.steps[4].phase, "award_pending", "expected workflow steps to include pending awards")
    assertTrue(snapshot.steps[4].active == true, "expected current workflow step to be marked active")
    assertEqual(snapshot.steps[5].phase, "award_confirmed", "expected workflow steps to include confirmed awards")
    assertEqual(snapshot.steps[6].phase, "trade_pending", "expected workflow steps to include pending trades")
    assertEqual(snapshot.steps[7].phase, "trade_confirmed", "expected workflow steps to include completed trades")
    assertEqual(snapshot.raidNum, 1, "expected workflow to retain loot-window raid")
    assertEqual(snapshot.selectedItemKey, "item:92001", "expected workflow to retain selected item key")
    assertEqual(snapshot.rollSessionId, "ROLL:1", "expected workflow to retain roll session")
    assertEqual(snapshot.pendingAward.playerName, "Tester", "expected workflow to retain queued award target")
    assertEqual(#snapshot.recentReceipts, 20, "expected recent receipt diagnostics to be bounded")
    assertEqual(snapshot.recentReceipts[1].msg, "receipt-3", "expected oldest diagnostics to be dropped first")
    assertEqual(snapshot.recentReceipts[20].msg, "receipt-22", "expected newest receipt to be retained")
end)

test("loot receipts classify normal receipts passive winners and ignored messages", function()
    local h = newHarness()
    h:load("!KRT/Services/Loot/Receipts.lua")
    local Receipts = h.addon.Services.Loot._Receipts
    local link = "|cff0070dd|Hitem:92011::::::::|h[Receipt Blade]|h|r"

    local normal = Receipts.FromParsedLoot({
        msg = "normal-loot",
        playerName = "Tester",
        itemLink = link,
        itemCount = 1,
        passiveGroupLoot = false,
    })
    assertEqual(normal.kind, "loot_received", "expected ordinary loot receipts to create loot records")
    assertEqual(Receipts.ShouldCreateRecord(normal), true, "expected ordinary loot receipts to be recordable")

    local passive = Receipts.FromParsedLoot({
        msg = "passive-winner",
        playerName = "Tester",
        itemLink = link,
        itemCount = 1,
        rollType = h.rollTypes.GREED,
        rollValue = 88,
        passiveGroupLoot = true,
        parsedGroupLoot = {
            kind = "winner",
            sessionId = "GL:7",
            rollId = 91,
        },
    })
    assertEqual(passive.kind, "group_winner", "expected passive winner receipts to be classified explicitly")
    assertEqual(passive.rollSessionId, "GL:7", "expected passive winner receipt to retain session id")
    assertEqual(passive.rollId, 91, "expected passive winner receipt to retain native roll id")
    assertEqual(Receipts.ShouldCreateRecord(passive), true, "expected passive winners to be recordable")

    local ignored = Receipts.FromParsedLoot({
        msg = "no-item",
        playerName = "Tester",
        passiveGroupLoot = true,
    })
    assertEqual(ignored.kind, "ignored", "expected itemless messages to be classified as ignored")
    assertEqual(Receipts.ShouldCreateRecord(ignored), false, "expected itemless messages to avoid record creation")
end)

test("loot record builder appends canonical rows with stable loot nids", function()
    local h = newHarness()
    h:load("!KRT/Services/Loot/Records.lua")
    local Records = h.addon.Services.Loot._Records
    local raid = {
        loot = {},
        nextLootNid = 7,
    }

    local row, lootNid = Records.Append(raid, {
        itemId = 92021,
        itemName = "Record Blade",
        itemString = "item:92021",
        itemLink = "|cff0070dd|Hitem:92021::::::::|h[Record Blade]|h|r",
        itemRarity = 3,
        itemTexture = "record-icon",
        itemCount = 2,
        looterNid = 4,
        rollType = h.rollTypes.MAINSPEC,
        rollValue = 99,
        rollSessionId = "ROLL:7",
        bossNid = 11,
        lootSource = {
            kind = "boss",
            bossNid = 11,
        },
        time = 1234,
    })

    assertEqual(lootNid, 7, "expected append to allocate current nextLootNid")
    assertEqual(raid.nextLootNid, 8, "expected append to advance nextLootNid")
    assertEqual(#raid.loot, 1, "expected append to insert exactly one row")
    assertEqual(raid.loot[1], row, "expected append to return inserted row")
    assertEqual(row.lootNid, 7, "expected inserted row to preserve allocated lootNid")
    assertEqual(row.itemCount, 2, "expected inserted row to preserve item count")
    assertEqual(row.looterNid, 4, "expected inserted row to preserve looter nid")
    assertEqual(row.lootSource.kind, "boss", "expected inserted row to preserve source provenance")
end)

test("trade-only loot creates a reusable lootNid", function()
    local h = newHarness()
    local link = h.registerItem(9100, "Tradeblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end

    h:load("!KRT/Services/Raid.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")
    h:load("!KRT/Controllers/Logger.lua")

    local Raid = h.addon.Services.Raid
    local lootNid = Raid:LogTradeOnlyLoot(link, "Alice", h.rollTypes.MAINSPEC, 98, 1, "TRADE_ONLY_TEST", 1, 10, "roll-session-1")
    assertTrue((tonumber(lootNid) or 0) > 0, "expected trade-only path to create a lootNid")
    assertEqual(Raid:GetLootNidByRollSessionId("roll-session-1", 1, "Alice", 10), lootNid, "expected rollSessionId lookup to resolve trade-only loot")

    local request = {
        lootNid = lootNid,
        looter = "Alice",
        rollType = h.rollTypes.RESERVED,
        rollValue = 77,
        source = "TEST_TRADE_ONLY",
        raidId = 1,
    }
    h.Bus.TriggerEvent(h.addon.Events.Internal.LoggerLootLogRequest, request)
    local ok = request.ok
    assertTrue(ok == true, "expected logger update to reuse trade-only lootNid")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(raid.loot[1].lootNid, lootNid, "expected trade-only entry to keep its lootNid")
    assertEqual(raid.loot[1].rollType, h.rollTypes.RESERVED, "expected logger update to mutate same entry")
    assertEqual(raid.loot[1].rollValue, 77, "expected logger update to keep same entry")
end)

test("raid loot records resolve roll session looter through current query facade", function()
    local h = newHarness()
    local link = h.registerItem(9166, "LootRecordFacadeBlade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "OtherRaider", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {
                {
                    lootNid = 1,
                    itemId = 9166,
                    itemName = "LootRecordFacadeBlade",
                    itemLink = link,
                    itemString = h.addon.Item.GetItemStringFromLink(link),
                    looterNid = 55,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 88,
                    rollSessionId = "ROLL:Q2",
                    bossNid = 10,
                    targetLooter = "TargetRaider",
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 2,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")

    local queryCalls = 0
    local currentQueries = {
        ResolveLootLooterName = function(self, raid, entry)
            queryCalls = queryCalls + 1
            assertEqual(entry.lootNid, 1, "expected query facade to inspect seeded loot")
            return entry.targetLooter
        end,
    }
    h.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    local Raid = h.addon.Services.Raid
    local lootNid = Raid:GetLootNidByRollSessionId("ROLL:Q2", 1, "TargetRaider", 10)

    assertEqual(lootNid, 1, "expected roll-session lookup to use current query facade")
    assertEqual(queryCalls, 1, "expected current query facade to be called once")
end)

test("trade-only loot reuses matching fallback rows instead of duplicating", function()
    local h = newHarness()
    local link = h.registerItem(90012, "Trade Merge Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Loot = h.addon.Services.Loot

    local first = Loot:LogTradeOnlyLoot(link, "Trader", h.rollTypes.MAINSPEC, 91, 1, "TRADE_ONLY", 1, 0, "ROLL:MERGE")
    local second = Loot:LogTradeOnlyLoot(link, "Trader", h.rollTypes.MAINSPEC, 97, 1, "TRADE_ONLY", 1, 0, "ROLL:MERGE")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(first, second, "expected matching trade-only fallback to reuse the original lootNid")
    assertEqual(#raid.loot, 1, "expected matching trade-only fallback to avoid duplicate records")
    assertEqual(raid.loot[1].rollValue, 97, "expected reused fallback row to keep the stronger resolved roll value")
end)

test("trade-only loot append patches runtime without full cache invalidation", function()
    local h = newHarness()
    local link = h.registerItem(9101, "Runtime Tradeblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", class = "MAGE" },
            },
            bossKills = {
                { bossNid = 10, name = "Sapphiron", time = 1000 },
            },
            loot = {},
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h:load("!KRT/Services/Raid.lua")
    local raid = h.Database.EnsureRaidById(1)
    local runtimeBefore = h.store:EnsureRaidRuntime(raid)

    local lootNid = h.addon.Services.Loot:LogTradeOnlyLoot(link, "Alice", h.rollTypes.MAINSPEC, 98, 1, "TRADE_ONLY_TEST", 1, 10, "roll-session-1")
    local runtimeAfter = h.store:EnsureRaidRuntime(raid)

    assertTrue((tonumber(lootNid) or 0) > 0, "expected trade-only path to create a lootNid")
    assertTrue(runtimeAfter == runtimeBefore, "expected trade-only append to preserve existing runtime table")
    assertEqual(runtimeAfter.lootIdxByNid[lootNid], 1, "expected appended trade-only loot to patch runtime index")
    assertTrue(runtimeAfter.lootByNid[lootNid] == raid.loot[1], "expected appended trade-only loot to patch runtime row lookup")
end)

test("loot source resolver filters candidates by raid and mode", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91710] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
                modes = { normal10 = true },
            },
            {
                npcId = 36612,
                npcName = "Lord Marrowgar",
                raid = "Icecrown Citadel",
                kind = "boss",
                modes = { normal10 = true },
            },
            {
                npcId = 15954,
                npcName = "Noth the Plaguebringer",
                raid = "Naxxramas",
                kind = "boss",
                modes = { normal25 = true },
            },
        },
    })

    local resolved = h.addon.LootSources.FindSource(91710, {
        raid = "Naxxramas",
        difficulty = 3,
        raidSize = 10,
    })

    assertEqual(resolved.reason, nil, "expected a resolved source")
    assertEqual(resolved.npcId, 15953, "expected the Naxxramas source to match")
    assertEqual(resolved.npcName, "Grand Widow Faerlina", "expected resolved boss name")
    assertEqual(resolved.kind, "boss", "expected boss source kind")
    assertEqual(resolved.confidence, "exact", "expected exact source confidence")
    assertEqual(resolved.sourceKey, "naxxramas|boss|15953|grand widow faerlina|normal10", "expected source key to include raid, source, and mode")
end)

test("loot source resolver returns shared candidates without context", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91712] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })

    local resolved = h.addon.LootSources.FindSource(91712)

    assertEqual(resolved.reason, "shared", "expected shared boss item to return structured shared context")
    assertEqual(resolved.kind, "shared", "expected shared boss item kind")
    assertEqual(resolved.npcName, "Shared", "expected shared display label")
    assertTrue(resolved.shared == true, "expected shared marker")
    assertTextContains(resolved.sourceKey, "shared|", "expected shared result to expose a compact shared source key")
    assertEqual(#resolved.candidates, 2, "expected both candidates to be reported")
    assertEqual(resolved.candidates[1].npcName, "Grand Widow Faerlina", "expected first shared source candidate")
    assertEqual(resolved.candidates[1].sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected first shared candidate source key")
    assertEqual(resolved.candidates[2].npcName, "Noth the Plaguebringer", "expected second shared source candidate")
    assertEqual(resolved.candidates[2].sourceKey, "naxxramas|boss|15954|noth the plaguebringer|any", "expected second shared candidate source key")
end)

test("loot source resolver uses recent context for shared boss items", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91716] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })

    local resolved = h.addon.LootSources.FindSource(91716, {
        raid = "Naxxramas",
        recentSourceNpcId = 15953,
        recentSourceName = "Grand Widow Faerlina",
    })

    assertEqual(resolved.reason, nil, "expected recent context to resolve shared loot")
    assertEqual(resolved.npcId, 15953, "expected recent source npc id to select Faerlina")
    assertEqual(resolved.npcName, "Grand Widow Faerlina", "expected recent source name to select Faerlina")
    assertEqual(resolved.kind, "boss", "expected resolved shared loot to bind to a boss")
    assertEqual(resolved.confidence, "shared-context", "expected shared context confidence")
    assertTrue(resolved.shared == true, "expected shared marker to stay visible")
    assertEqual(#resolved.candidates, 2, "expected all shared boss candidates to remain visible")
end)

test("loot source resolver ignores malformed candidates", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91713] = {
            { kind = "boss" },
            { npcId = 0, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15953, npcName = "", raid = "Naxxramas", kind = "boss" },
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "", kind = "boss" },
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "unknown" },
        },
    })

    local resolved = h.addon.LootSources.FindSource(91713)

    assertEqual(resolved.reason, "missing", "expected malformed candidates to be ignored")
    assertEqual(#resolved.candidates, 0, "expected no malformed candidates to be reported")
end)

test("loot source candidates do not expose mutable mode data", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91714] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
                modes = { normal10 = true },
            },
        },
    })

    local candidates = h.addon.LootSources.GetCandidates(91714)
    candidates[1].modes.normal10 = false
    candidates[1].modes.heroic25 = true

    local freshCandidates = h.addon.LootSources.GetCandidates(91714)

    assertTrue(freshCandidates[1].modes.normal10 == true, "expected mode flags to be copied from backing data")
    assertTrue(freshCandidates[1].modes.heroic25 == nil, "expected returned mode mutations not to affect backing data")
end)

test("loot source resolver filters classic raid sizes by mode", function()
    local h = newHarness()
    h:load("!KRT/Modules/LootSources.lua")

    h.addon.LootSources._SetDataForTests({
        [91715] = {
            {
                npcId = 10184,
                npcName = "Onyxia",
                raid = "Onyxia's Lair",
                kind = "boss",
                modes = { normal40 = true },
            },
            {
                npcId = 10184,
                npcName = "Onyxia",
                raid = "Onyxia's Lair",
                kind = "boss",
                modes = { normal25 = true },
            },
        },
    })

    local resolved = h.addon.LootSources.FindSource(91715, {
        raid = "Onyxia's Lair",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(resolved.reason, nil, "expected a resolved classic-size source")
    assertEqual(resolved.npcId, 10184, "expected Onyxia source to match")
    assertTrue(resolved.modes.normal40 == true, "expected the 40-player source to match")
    assertTrue(resolved.modes.normal25 == nil, "expected the 25-player source to be filtered out")
end)

local function loadRealLootSourceDataset(h)
    local files = {
        "!KRT/Modules/Dataset/LootSources/Vanilla.lua",
        "!KRT/Modules/Dataset/LootSources/BurningCrusade.lua",
        "!KRT/Modules/Dataset/LootSources/Wrath.lua",
        "!KRT/Modules/LootSourceCandidates.lua",
        "!KRT/Modules/Dataset/LootSourcesData.lua",
        "!KRT/Modules/LootSources.lua",
    }

    for i = 1, #files do
        local chunk, err = loadfile(files[i])
        if not chunk then
            error(err, 0)
        end
        chunk("!KRT", h.addon)
    end
end

test("real loot source dataset includes AtlasLoot Naxxramas 25 Anub'Rekhan drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local expectations = {
        [39701] = "Dawnwalkers",
        [39703] = "Rescinding Grips",
        [39719] = "Mantle of the Locusts",
    }

    for itemId, itemName in pairs(expectations) do
        local resolved = h.addon.LootSources.FindSource(itemId, {
            raid = "Naxxramas",
            difficulty = 4,
            raidSize = 25,
        })

        assertEqual(resolved.reason, nil, "expected " .. itemName .. " to resolve from real Naxxramas dataset")
        assertEqual(resolved.npcId, 15956, "expected " .. itemName .. " to resolve to Anub'Rekhan")
        assertEqual(resolved.npcName, "Anub'Rekhan", "expected " .. itemName .. " source name")
        assertEqual(resolved.kind, "boss", "expected " .. itemName .. " to resolve as boss loot")
    end
end)

test("real loot source dataset includes representative AtlasLoot Vanilla raid drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local resolved = h.addon.LootSources.FindSource(18832, {
        raid = "Molten Core",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(resolved.reason, nil, "expected Brutality Blade to resolve from Molten Core")
    assertEqual(resolved.npcId, 12057, "expected Brutality Blade to resolve to Garr")
    assertEqual(resolved.npcName, "Garr", "expected Vanilla source name")
    assertTrue(resolved.modes.normal40 == true, "expected Vanilla raid mode")
end)

test("real loot source dataset includes representative AtlasLoot TBC raid drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local resolved = h.addon.LootSources.FindSource(32351, {
        raid = "Black Temple",
        difficulty = 2,
        raidSize = 25,
        recentSourceNpcId = 23420,
    })

    assertEqual(resolved.reason, nil, "expected Elunite Empowered Bracers to resolve from Black Temple")
    assertEqual(resolved.npcId, 23420, "expected Elunite Empowered Bracers to resolve to Essence of Anger")
    assertEqual(resolved.npcName, "Essence of Anger", "expected TBC source name")
    assertTrue(resolved.modes.normal25 == true, "expected TBC raid mode")
end)

test("real loot source dataset includes representative AtlasLoot Wrath raid quest drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local resolved = h.addon.LootSources.FindSource(44650, {
        raid = "The Eye of Eternity",
        difficulty = 3,
        raidSize = 10,
    })

    assertEqual(resolved.reason, nil, "expected Heart of Magic to resolve from The Eye of Eternity")
    assertEqual(resolved.npcId, 28859, "expected Heart of Magic to resolve to Malygos")
    assertEqual(resolved.npcName, "Malygos", "expected Wrath source name")
    assertTrue(resolved.modes.normal10 == true, "expected Wrath 10-player raid mode")
end)

test("real loot source dataset includes representative AtlasLoot world boss drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local classic = h.addon.LootSources.FindSource(17070, {
        raid = "Azshara",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(classic.reason, nil, "expected Fang of the Mystics to resolve from Azshara")
    assertEqual(classic.npcId, 6109, "expected Fang of the Mystics to resolve to Azuregos")
    assertEqual(classic.npcName, "Azuregos", "expected Classic world boss source name")
    assertTrue(classic.modes.normal40 == true, "expected Classic world boss mode")

    local burningCrusade = h.addon.LootSources.FindSource(30733, {
        raid = "Hellfire Peninsula",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(burningCrusade.reason, nil, "expected Hope Ender to resolve from Hellfire Peninsula")
    assertEqual(burningCrusade.npcId, 18728, "expected Hope Ender to resolve to Doom Lord Kazzak")
    assertEqual(burningCrusade.npcName, "Doom Lord Kazzak", "expected TBC world boss source name")
    assertTrue(burningCrusade.modes.normal40 == true, "expected TBC world boss mode")
end)

test("real loot source dataset preserves AtlasLoot Naxxramas 25 shared drops", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local resolved = h.addon.LootSources.FindSource(40080, {
        raid = "Naxxramas",
        difficulty = 4,
        raidSize = 25,
    })

    assertEqual(resolved.reason, "shared", "expected Lost Jewel to remain shared without recent context")
    assertEqual(resolved.kind, "shared", "expected Lost Jewel to resolve as shared loot")
    assertTrue(#resolved.candidates >= 3, "expected Lost Jewel to keep multiple Naxxramas 25 source candidates")

    local ring = h.addon.LootSources.FindSource(40108, {
        raid = "Naxxramas",
        difficulty = 4,
        raidSize = 25,
    })
    local ringSources = {}
    for i = 1, #(ring.candidates or {}) do
        ringSources[ring.candidates[i].npcName] = true
    end

    assertEqual(ring.reason, "shared", "expected Seized Beauty to remain shared without recent context")
    assertEqual(ring.kind, "shared", "expected Seized Beauty to resolve as shared loot")
    assertTextContains(ring.sourceKey, "shared|", "expected Seized Beauty to expose a shared source key")
    assertTrue(ringSources["Anub'Rekhan"] == true, "expected Seized Beauty to include Anub'Rekhan")
    assertTrue(ringSources["Grand Widow Faerlina"] == true, "expected Seized Beauty to include Grand Widow Faerlina")
    assertTrue(ringSources["Instructor Razuvious"] == true, "expected Seized Beauty to include Instructor Razuvious")
    assertTrue(ringSources["Noth the Plaguebringer"] == true, "expected Seized Beauty to include Noth the Plaguebringer")
    assertTrue(ringSources["Patchwerk"] == true, "expected Seized Beauty to include Patchwerk")
    for i = 1, #(ring.candidates or {}) do
        assertTextContains(ring.candidates[i].sourceKey, "naxxramas|boss|", "expected Seized Beauty candidates to expose source keys")
        assertTextContains(ring.candidates[i].sourceKey, "normal25", "expected Seized Beauty candidate keys to keep Wrath 25 mode")
    end
end)

test("real loot source dataset keeps Onyxia classic and level 80 modes separate", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local classic = h.addon.LootSources.FindSource(17064, {
        raid = "Onyxia's Lair",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(classic.reason, nil, "expected classic Onyxia loot to resolve in 40-player mode")
    assertEqual(classic.npcId, 10184, "expected classic Onyxia source to match")
    assertTrue(classic.modes.normal40 == true, "expected classic Onyxia loot to stay in normal40 mode")
    assertTrue(classic.modes.normal10 == nil, "expected classic Onyxia loot not to inherit level 80 10-player mode")
    assertTrue(classic.modes.normal25 == nil, "expected classic Onyxia loot not to inherit level 80 25-player mode")

    local level80Ten = h.addon.LootSources.FindSource(49307, {
        raid = "Onyxia's Lair",
        difficulty = 3,
        raidSize = 10,
    })

    assertEqual(level80Ten.reason, nil, "expected AtlasLoot Onyxia level 80 10-player loot to resolve")
    assertEqual(level80Ten.npcId, 10184, "expected level 80 10-player Onyxia source to match")
    assertTrue(level80Ten.modes.normal10 == true, "expected level 80 Onyxia 10-player loot to use normal10 mode")
    assertTrue(level80Ten.modes.normal40 == nil, "expected level 80 Onyxia 10-player loot not to use classic mode")

    local level80TwentyFive = h.addon.LootSources.FindSource(49491, {
        raid = "Onyxia's Lair",
        difficulty = 4,
        raidSize = 25,
    })

    assertEqual(level80TwentyFive.reason, nil, "expected AtlasLoot Onyxia level 80 25-player loot to resolve")
    assertEqual(level80TwentyFive.npcId, 10184, "expected level 80 25-player Onyxia source to match")
    assertTrue(level80TwentyFive.modes.normal25 == true, "expected level 80 Onyxia 25-player loot to use normal25 mode")
    assertTrue(level80TwentyFive.modes.normal40 == nil, "expected level 80 Onyxia 25-player loot not to use classic mode")
end)

test("real loot source dataset keeps Classic and Wrath Naxxramas modes separate", function()
    local h = newHarness()
    loadRealLootSourceDataset(h)

    local classic = h.addon.LootSources.FindSource(23054, {
        raid = "Naxxramas",
        difficulty = 1,
        raidSize = 40,
    })

    assertEqual(classic.reason, nil, "expected classic Naxxramas loot to resolve")
    assertTrue(classic.modes.normal40 == true, "expected classic Naxxramas normal40 mode")
    assertTrue(classic.modes.normal10 == nil, "expected classic Naxxramas not to inherit Wrath 10-player mode")
    assertTrue(classic.modes.normal25 == nil, "expected classic Naxxramas not to inherit Wrath 25-player mode")

    local wrath = h.addon.LootSources.FindSource(39719, {
        raid = "Naxxramas",
        difficulty = 4,
        raidSize = 25,
    })

    assertEqual(wrath.reason, nil, "expected Wrath Naxxramas loot to resolve")
    assertTrue(wrath.modes.normal25 == true, "expected Wrath Naxxramas 25-player mode")
    assertTrue(wrath.modes.normal40 == nil, "expected Wrath Naxxramas not to inherit classic mode")
end)

test("group loot need selections log passive NE history on loot receipt", function()
    local h = newHarness()
    local link = h.registerItem(9150, "Needblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self" then
            return 77, link
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    assertTrue(Raid:CanObservePassiveLoot(), "expected passive loot logging to stay enabled for group loot")
    assertEqual(Raid:AddGroupLootMessage("need-select-self"), "selection", "expected self need selection to queue passive history")

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected group loot receipt to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected queued need selection to classify the loot as NE")
    assertEqual(raid.loot[1].rollValue, 0, "expected passive group loot entries to default rollValue to 0")
end)

test("loot receipts without scoped context fall back to trash", function()
    local h = newHarness()
    local link = h.registerItem(9155, "Recovery Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, name = "Sapphiron", time = 990 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    _G.GetLootMethod = function()
        return "master", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 2, "expected missing scoped context to create a TrashMob bucket")
    assertEqual(raid.bossKills[2].name, "_TrashMob_", "expected loot fallback to create the canonical TrashMob boss entry")
    assertEqual(raid.loot[1].bossNid, 11, "expected loot without scoped context to attach to TrashMob")
end)

test("loot receipts reuse short-lived boss event context even if lastBoss is cleared", function()
    local h = newHarness()
    local link = h.registerItem(9157, "Event Context Blade")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Sapphiron"), 1, "expected the boss event to materialize a boss kill")
    h.Database.SetLastBoss(nil)

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected event-context recovery to reuse the boss kill instead of creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 1, "expected loot logging to attach to the boss carried by the event context")
    assertEqual(h.Database.GetLastBoss(), 1, "expected event-context recovery to restore lastBoss after an explicit clear")
end)

test("loot window snapshot keeps first boss loot after event context expires", function()
    local h = newHarness()
    local link = h.registerItem(9158, "Window Snapshot Blade")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Sapphiron"), 1, "expected the boss kill to create a boss context")

    currentTime = 1005
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {}, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected loot window open to snapshot the boss context"
    )

    currentTime = 1040
    h.feature.lootState.opened = true
    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)
    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected the first delayed boss loot to avoid creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 1, "expected the delayed first boss loot to reuse the window snapshot")
end)

test("loot window source persists boss snapshot metadata into loot rows", function()
    local h = newHarness()
    local link = h.registerItem(91581, "Window Source Blade")
    local itemKey = h.addon.Item.GetItemStringFromLink(link)
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "source-loot-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Sapphiron"), 1, "expected the boss kill to create a boss context")

    currentTime = 1005
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = itemKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected loot window open to create a boss snapshot source"
    )

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected an active loot source after LOOT_OPENED")
    assertEqual(source.kind, "boss", "expected the active loot source to classify the window as boss loot")
    assertEqual(source.bossNid, 1, "expected the active loot source to keep the boss nid")
    assertTrue((tonumber(source.snapshotId) or 0) > 0, "expected the active loot source to expose the item snapshot id")
    assertEqual(source.openedAt, 1005, "expected the active loot source to keep the LOOT_OPENED timestamp")

    h.feature.lootState.opened = true
    currentTime = 1006
    Raid:AddLoot("source-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected the boss loot receipt to log one row")
    assertTrue(type(raid.loot[1].lootSource) == "table", "expected the logged loot row to persist lootSource metadata")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected the logged loot row to keep the boss source kind")
    assertEqual(raid.loot[1].lootSource.bossNid, 1, "expected the logged loot row to keep the boss source nid")
    assertEqual(raid.loot[1].lootSource.snapshotId, source.snapshotId, "expected the logged loot row to retain the originating snapshot id")
    assertEqual(raid.loot[1].lootSource.openedAt, 1005, "expected the logged loot row to retain the LOOT_OPENED timestamp")
end)

test("loot window keeps boss association for later boss items after event context expires", function()
    local h = newHarness()
    local firstLink = h.registerItem(9159, "First Boss Blade")
    local secondLink = h.registerItem(9162, "Second Boss Blade")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-first" then
            return firstLink
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-second" then
            return secondLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Sapphiron"), 1, "expected the boss kill to create a boss context")

    h.feature.lootState.opened = true
    Raid:AddLoot("loot-receive-first")

    currentTime = 1031
    h.Database.SetLastBoss(nil)
    Raid:AddLoot("loot-receive-second")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected later boss loot in the same window to avoid creating TrashMob")
    assertEqual(#raid.loot, 2, "expected both boss loot items to be recorded")
    assertEqual(raid.loot[1].bossNid, 1, "expected the first boss loot item to attach to the boss")
    assertEqual(raid.loot[2].bossNid, 1, "expected the later boss loot item to reuse the loot-window boss context")
end)

test("trade-only loot reuses boss context captured for the award session", function()
    local h = newHarness()
    local link = h.registerItem(9163, "Trade Session Blade")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Sapphiron"), 1, "expected the boss kill to create a boss context")

    currentTime = 1005
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {}, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected loot window open to snapshot the boss context"
    )

    currentTime = 1035
    assertEqual(
        Raid:FindAndRememberBossContextForLootSession(1, "RS:trade", {
            allowLootWindowContext = true,
            allowContextRecovery = false,
            ttlSeconds = 60,
        }),
        1,
        "expected the award session to capture the boss context from the loot window"
    )

    Raid:ClearLootWindowBossContext()
    currentTime = 1045
    local lootNid = Raid:LogTradeOnlyLoot(link, "Tester", h.rollTypes.HOLD, 0, 1, "TRADE_ONLY_TEST", 1, nil, "RS:trade")

    local raid = h.Database.EnsureRaidById(1)
    assertTrue((tonumber(lootNid) or 0) > 0, "expected the trade-only path to create a loot entry")
    assertEqual(#raid.loot, 1, "expected the trade-only path to create one loot entry")
    assertEqual(raid.loot[1].bossNid, 1, "expected the trade-only path to reuse the session boss context")
end)

test("raid state resolves loot session boss through current query facade", function()
    local h = newHarness()
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 1, name = "OriginalBoss", time = 900 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 2,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")

    local queryCalls = 0
    local currentQueries = {
        FindBossByNid = function(self, raid, bossNid)
            queryCalls = queryCalls + 1
            assertEqual(bossNid, 99, "expected query facade to inspect the remembered boss nid")
            return { bossNid = 99, name = "FacadeBoss" }
        end,
    }
    h.Database.GetRaidQueriesOrNil = function()
        return currentQueries
    end

    local Raid = h.addon.Services.Raid
    Raid:SetBossContextForLootSession(1, "ROLL:Q3", 99, 60)

    local bossNid = Raid:FindAndRememberBossContextForLootSession(1, "ROLL:Q3", {
        ttlSeconds = 60,
    })

    assertEqual(bossNid, 99, "expected session lookup to use current query facade")
    assertEqual(queryCalls, 1, "expected current query facade to be called once")
end)

test("reopening a partially looted boss corpse after trash reuses the original boss snapshot", function()
    local h = newHarness()
    local bossLink1 = h.registerItem(9164, "Boss Snapshot One")
    local bossLink2 = h.registerItem(9165, "Boss Snapshot Two")
    local bossLink3 = h.registerItem(9166, "Boss Snapshot Three")
    local bossLink4 = h.registerItem(9167, "Boss Snapshot Four")
    local trashLink = h.registerItem(9168, "Trash Snapshot One")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "boss-loot-three" then
            return bossLink3
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "boss-loot-four" then
            return bossLink4
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "trash-loot-one" then
            return trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local bossKey1 = h.addon.Item.GetItemStringFromLink(bossLink1)
    local bossKey2 = h.addon.Item.GetItemStringFromLink(bossLink2)
    local bossKey3 = h.addon.Item.GetItemStringFromLink(bossLink3)
    local bossKey4 = h.addon.Item.GetItemStringFromLink(bossLink4)

    assertEqual(Raid:AddBoss("Anub'Rekhan"), 1, "expected the boss kill to create a boss context")
    currentTime = 1005
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey1, count = 1 },
            { itemKey = bossKey2, count = 1 },
            { itemKey = bossKey3, count = 1 },
            { itemKey = bossKey4, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected the first boss open to snapshot the whole corpse loot"
    )
    Raid:_ConsumeLootWindowItemContext(bossLink1)
    Raid:_ConsumeLootWindowItemContext(bossLink2)

    Raid:ClearLootWindowBossContext()
    h.feature.lootState.opened = true
    currentTime = 1040
    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)
    Raid:AddLoot("trash-loot-one")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected trash loot in the middle to be recorded")
    assertEqual(raid.loot[1].bossNid, 2, "expected the interleaved trash loot to use TrashMob")

    Raid:ClearLootWindowBossContext()
    currentTime = 1025
    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey3, count = 1 },
            { itemKey = bossKey4, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected the reopened boss corpse to reactivate the original boss snapshot"
    )

    Raid:AddLoot("boss-loot-three")
    Raid:AddLoot("boss-loot-four")

    assertEqual(#raid.loot, 3, "expected the reopened boss corpse to add the remaining two boss items")
    assertEqual(raid.loot[2].bossNid, 1, "expected the third logged item to return to the boss context")
    assertEqual(raid.loot[3].bossNid, 1, "expected the fourth logged item to return to the boss context")
end)

test("loot window opened on trash blocks recent boss event recovery", function()
    local h = newHarness()
    local trashLink = h.registerItem(9169, "Trash Context Belt")
    local trashKey = h.addon.Item.GetItemStringFromLink(trashLink)
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == "Creature-0-0-0-0-15989-0000000000" then
            return 15989
        end
        return 0
    end
    _G.UnitExists = function(unit)
        return unit == "mouseover"
    end
    _G.UnitGUID = function(unit)
        if unit == "mouseover" then
            return "Creature-0-0-0-0-15989-0000000000"
        end
        return nil
    end
    _G.UnitName = function(unit)
        if unit == "mouseover" then
            return "Naxxramas Cultist"
        end
        return unit
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "trash-loot-self" then
            return trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Grand Widow Faerlina", nil, nil, 15953), 1, "expected the boss kill to create the recent boss event context")

    h.feature.lootState.opened = true
    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = trashKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        0,
        "expected an explicit trash corpse open to block boss recovery"
    )

    Raid:AddLoot("trash-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 2, "expected trash loot to create a TrashMob bucket instead of reusing the boss")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected the original boss entry to stay intact")
    assertEqual(raid.bossKills[2].name, "_TrashMob_", "expected the opened trash corpse to stay on TrashMob")
    assertEqual(raid.loot[1].bossNid, 2, "expected trash loot to avoid inheriting the recent boss context")
end)

test("loot window source classifies blocked non-boss opens as trash", function()
    local h = newHarness()
    local trashLink = h.registerItem(91691, "Trash Source Belt")
    local trashKey = h.addon.Item.GetItemStringFromLink(trashLink)
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == "Creature-0-0-0-0-15989-0000000000" then
            return 15989
        end
        return 0
    end
    _G.UnitExists = function(unit)
        return unit == "mouseover"
    end
    _G.UnitGUID = function(unit)
        if unit == "mouseover" then
            return "Creature-0-0-0-0-15989-0000000000"
        end
        return nil
    end
    _G.UnitName = function(unit)
        if unit == "mouseover" then
            return "Naxxramas Cultist"
        end
        return unit
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "trash-source-self" then
            return trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = trashKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        0,
        "expected an explicit trash corpse open to avoid boss snapshot creation"
    )

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected a loot source even when the open is blocked for boss recovery")
    assertEqual(source.kind, "trash", "expected blocked non-boss openings to classify as trash")
    assertEqual(source.sourceNpcId, 15989, "expected trash loot source to preserve the source npc id")
    assertEqual(source.sourceName, "Naxxramas Cultist", "expected trash loot source to preserve the source name")

    h.feature.lootState.opened = true
    Raid:AddLoot("trash-source-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(raid.loot[1].lootSource.kind, "trash", "expected trash loot rows to persist the trash source kind")
    assertEqual(raid.loot[1].lootSource.bossNid, 1, "expected trash loot rows to bind lootSource to the TrashMob boss bucket")
    assertEqual(raid.loot[1].lootSource.sourceNpcId, 0, "expected fallback trash provenance to avoid stale source npc metadata")
    assertEqual(raid.loot[1].lootSource.sourceName, "_TrashMob_", "expected fallback trash provenance to use the TrashMob source name")
end)

test("loot window recent trash death blocks boss event recovery without unit probes", function()
    local h = newHarness()
    local trashLink = h.registerItem(91692, "Recent Death Trash Belt")
    local trashKey = h.addon.Item.GetItemStringFromLink(trashLink)
    local currentTime = 1000
    local trashGuid = "Creature-0-0-0-0-15989-0000000000"

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.UnitExists = function()
        return false
    end
    _G.bit = {
        band = function()
            return 0
        end,
    }
    _G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == trashGuid then
            return 15989
        end
        return 0
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "recent-trash-loot-self" then
            return trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Grand Widow Faerlina", nil, nil, 15953), 1, "expected boss event context")
    currentTime = 1005
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005, "UNIT_DIED", nil, nil, 0, trashGuid, "Naxxramas Cultist", 0)

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = trashKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        0,
        "expected recent trash death to block boss event recovery"
    )

    h.feature.lootState.opened = true
    Raid:AddLoot("recent-trash-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 2, "expected recent trash loot to create a TrashMob bucket")
    assertEqual(raid.bossKills[2].name, "_TrashMob_", "expected recent trash loot to avoid the boss context")
    assertEqual(raid.loot[1].bossNid, 2, "expected recent trash loot to bind to TrashMob")
end)

test("loot source modules load after item helpers and before ignored item tables", function()
    local file = assert(io.open("!KRT/!KRT.toc", "r"))
    local toc = file:read("*a")
    file:close()

    local itemIndex = string.find(toc, "Modules\\Item.lua", 1, true)
    local dataIndex = string.find(toc, "Modules\\Dataset\\LootSourcesData.lua", 1, true)
    local resolverIndex = string.find(toc, "Modules\\LootSources.lua", 1, true)
    local ignoredIndex = string.find(toc, "Modules\\Dataset\\IgnoredItems.lua", 1, true)

    assertTrue(itemIndex ~= nil, "expected Item module in TOC")
    assertTrue(dataIndex ~= nil, "expected LootSourcesData module in TOC")
    assertTrue(resolverIndex ~= nil, "expected LootSources module in TOC")
    assertTrue(ignoredIndex ~= nil, "expected IgnoredItems module in TOC")
    assertTrue(itemIndex < dataIndex, "expected LootSourcesData to load after Item")
    assertTrue(dataIndex < resolverIndex, "expected LootSources to load after LootSourcesData")
    assertTrue(resolverIndex < ignoredIndex, "expected LootSources to load before IgnoredItems")
end)

test("loot window recent boss death resolves boss context without raid target probes", function()
    local h = newHarness()
    local bossLink = h.registerItem(91703, "Recent Death Faerlina Mantle")
    local bossKey = h.addon.Item.GetItemStringFromLink(bossLink)
    local currentTime = 1000
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"
    local raidTargetProbeCount = 0

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetNumRaidMembers = function()
        return 40
    end

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == bossGuid then
            return 15953
        end
        return 0
    end
    _G.bit = {
        band = function()
            return 0
        end,
    }
    _G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
    _G.UnitExists = function(unit)
        if type(unit) == "string" and unit:match("^raid%d+target$") then
            raidTargetProbeCount = raidTargetProbeCount + 1
        end
        return false
    end
    _G.UnitGUID = function()
        return nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "boss-source-loot-self" then
            return bossLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, bossGuid, "Grand Widow Faerlina", 0)
    currentTime = 1005

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected recent boss death to create the boss context"
    )
    assertEqual(raidTargetProbeCount, 0, "expected recent boss death resolution to skip raid target probes")

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected an active boss loot source after recent boss death resolution")
    assertEqual(source.kind, "boss", "expected recent boss death resolution to classify the source as boss")
    assertEqual(source.sourceNpcId, 15953, "expected recent boss death resolution to preserve the boss npc id")

    h.feature.lootState.opened = true
    Raid:AddLoot("boss-source-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected recent boss death resolution to create one boss kill")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected the boss kill to use the death context boss name")
    assertEqual(raid.bossKills[1].sourceNpcId, 15953, "expected the boss kill to preserve the death context npc id")
    assertEqual(#raid.loot, 1, "expected item source boss loot to log one row")
    assertEqual(raid.loot[1].bossNid, 1, "expected recent boss death loot to bind to the resolved boss")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected recent boss death loot to persist boss source metadata")
    assertEqual(raid.loot[1].lootSource.sourceNpcId, 15953, "expected loot source metadata to keep the death context npc id")
end)

test("loot window mouseover boss resolves boss context without event recovery", function()
    local h = newHarness()
    local bossLink = h.registerItem(9170, "Faerlina Mantle")
    local bossKey = h.addon.Item.GetItemStringFromLink(bossLink)
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == "Creature-0-0-0-0-15953-0000000000" then
            return 15953
        end
        return 0
    end
    _G.UnitExists = function(unit)
        return unit == "mouseover"
    end
    _G.UnitGUID = function(unit)
        if unit == "mouseover" then
            return "Creature-0-0-0-0-15953-0000000000"
        end
        return nil
    end
    _G.UnitName = function(unit)
        if unit == "mouseover" then
            return "Grand Widow Faerlina"
        end
        return unit
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "boss-loot-self" then
            return bossLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddBoss("Grand Widow Faerlina", nil, nil, 15953), 1, "expected the boss kill to be logged before the later loot open")

    currentTime = 1040
    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)
    h.feature.lootState.opened = true

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected boss corpse mouseover to restore the boss context without event recovery"
    )

    Raid:AddLoot("boss-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected no TrashMob fallback for a boss corpse open")
    assertEqual(raid.loot[1].bossNid, 1, "expected the loot to stay attached to Grand Widow Faerlina")
end)

test("loot window does not scan dead raid targets during source recovery", function()
    local h = newHarness()
    local bossLink = h.registerItem(91702, "Raid Target Faerlina Mantle")
    local bossKey = h.addon.Item.GetItemStringFromLink(bossLink)
    local currentTime = 1000
    local bossNpcId = 15953
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"
    local raidTargetProbeCount = 0

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetNumRaidMembers = function()
        return 3
    end

    h.addon.BossIDs = {
        BossIDs = {
            [bossNpcId] = true,
        },
        GetBossName = function(_, npcId)
            if npcId == bossNpcId then
                return "Grand Widow Faerlina"
            end
            return nil
        end,
    }
    h.addon.GetCreatureId = function(guid)
        if guid == bossGuid then
            return bossNpcId
        end
        return 0
    end
    _G.UnitExists = function(unit)
        if type(unit) == "string" and unit:match("^raid%d+target$") then
            raidTargetProbeCount = raidTargetProbeCount + 1
        end
        return unit == "raid2target"
    end
    _G.UnitGUID = function(unit)
        if unit == "raid2target" then
            return bossGuid
        end
        return nil
    end
    _G.UnitIsDead = function(unit)
        return unit == "raid2target"
    end
    _G.UnitName = function(unit)
        if unit == "raid2target" then
            return "Grand Widow Faerlina"
        end
        return unit
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "raid-target-boss-loot-self" then
            return bossLink
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)
    h.feature.lootState.opened = true

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        0,
        "expected raid target source recovery to stay disabled during loot open"
    )
    assertEqual(raidTargetProbeCount, 0, "expected loot open to skip raid target probes")

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected an active loot source after context-free loot open")
    assertEqual(source.kind, "object", "expected raid target-only source recovery to classify as object")
    assertEqual(source.sourceNpcId, 0, "expected raid target-only source recovery to avoid npc metadata")

    Raid:AddLoot("raid-target-boss-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected raid target-only source recovery to avoid creating a boss kill")
    assertEqual(raid.bossKills[1].name, "_TrashMob_", "expected raid target-only source recovery to fall back to trash")
    assertEqual(#raid.loot, 1, "expected raid target boss loot to log one row")
    assertEqual(raid.loot[1].bossNid, 1, "expected raid target-only source recovery loot to bind to trash")
    assertEqual(raid.loot[1].lootSource.kind, "trash", "expected fallback loot source metadata to use trash provenance")
    assertEqual(raid.loot[1].lootSource.sourceName, "_TrashMob_", "expected fallback loot source metadata to use the TrashMob source name")
end)

test("loot window source marks context-free openings as object", function()
    local h = newHarness()
    local link = h.registerItem(91701, "Object Source Ring")
    local itemKey = h.addon.Item.GetItemStringFromLink(link)
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.UnitExists = function()
        return false
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "object-source-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = itemKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        0,
        "expected a context-free loot open to avoid inventing a boss snapshot"
    )

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected a loot source even without a boss or corpse unit")
    assertEqual(source.kind, "object", "expected context-free loot openings to classify as object")
    assertEqual(source.snapshotId, nil, "expected context-free object openings to have no snapshot id")

    h.feature.lootState.opened = true
    Raid:AddLoot("object-source-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected object-source loot to log one row")
    assertEqual(raid.loot[1].lootSource.kind, "trash", "expected object-source loot rows to persist fallback trash provenance")
    assertEqual(raid.loot[1].lootSource.bossNid, 1, "expected object-source loot rows to bind fallback provenance to the TrashMob boss nid")
    assertEqual(raid.loot[1].lootSource.sourceName, "_TrashMob_", "expected object-source loot rows to use the TrashMob source name")
end)

test("loot receipts do not recover boss context from the current target", function()
    local h = newHarness()
    local link = h.registerItem(9156, "Target Recovery Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    h.addon.BossIDs = {
        BossIDs = {
            [36612] = true,
        },
        GetBossName = function(_, npcId)
            if npcId == 36612 then
                return "Lord Marrowgar"
            end
            return nil
        end,
    }
    h.addon.GetCreatureId = function(guid)
        if guid == "Creature-0-0-0-0-36612-0000000000" then
            return 36612
        end
        return nil
    end
    _G.UnitGUID = function(unit)
        if unit == "target" then
            return "Creature-0-0-0-0-36612-0000000000"
        end
        return nil
    end
    _G.UnitName = function(unit)
        if unit == "target" then
            return "Lord Marrowgar"
        end
        return unit
    end
    _G.GetInstanceInfo = function()
        return "Icecrown Citadel", "raid", 4
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected loot logging to fall back to TrashMob when no scoped boss context exists")
    assertEqual(raid.bossKills[1].name, "_TrashMob_", "expected target heuristic recovery to stay disabled")
    assertEqual(raid.loot[1].bossNid, 1, "expected loot without scoped context to attach to TrashMob")
end)

test("group loot sessions skip boss association without relying on lastBoss", function()
    local h = newHarness()
    local link = h.registerItem(9158, "Scoped Context Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, name = "Sapphiron", time = 990 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    _G.GetLootMethod = function()
        return "needbeforegreed", nil, nil
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 91 then
            return link
        end
        return nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "greed-win-self" then
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    h.feature.raidState.bossEventContext = {
        raidNum = 1,
        bossNid = 10,
        name = "Sapphiron",
        source = "UNIT_DIED",
        seenAt = h.feature.Time.GetCurrentTime(),
    }

    Raid:AddPassiveLootRoll(91, 45000)
    h.feature.raidState.bossEventContext = nil
    h.Database.SetLastBoss(nil)

    assertEqual(Raid:AddGroupLootMessage("greed-win-self"), "winner", "expected passive winner message to be recognized")
    Raid:AddLoot("greed-win-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected passive group loot to avoid creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 0, "expected passive group loot to avoid source binding")
    assertEqual(raid.loot[1].lootSource, nil, "expected passive group loot to avoid source provenance")
    assertEqual(raid.loot[1].rollType, h.rollTypes.GREED, "expected passive group loot to keep roll type")
    assertEqual(raid.loot[1].rollValue, 88, "expected passive group loot to keep roll score")
end)

test("passive group loot parsed winner result is reused when logging loot", function()
    local h = newHarness()
    local link = h.registerItem(91581, "Parsed Winner Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    local winnerPatternCalls = 0
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "greed-win-self" then
            winnerPatternCalls = winnerPatternCalls + 1
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Loot = h.addon.Services.Loot

    local observedType, parsedLoot = Loot:GetGroupLootMessageResult("greed-win-self")
    assertEqual(observedType, "winner", "expected passive winner message to be recognized")
    Loot:AddLoot("greed-win-self", nil, nil, parsedLoot)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected parsed winner message to be logged")
    assertEqual(raid.loot[1].rollValue, 88, "expected parsed winner roll value to be reused")
    assertEqual(winnerPatternCalls, 1, "expected winner message to be parsed once across observe and log")
end)

test("loot service observes passive winner messages through one facade", function()
    local h = newHarness()
    local link = h.registerItem(915812, "Facade Winner Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "greed-win-self" then
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    local observedType, parsedLoot = Loot:ObservePassiveLootMessage("greed-win-self", true)

    assertEqual(observedType, "winner", "expected passive winner message to be observed through facade")
    assertEqual(parsedLoot.itemLink, link, "expected facade to return parsed passive loot payload")
    assertEqual(parsedLoot.rollValue, 88, "expected facade to preserve parsed roll value")
end)

test("loot service ignore group loot option suppresses passive group loot observation", function()
    local h = newHarness()
    local link = h.registerItem(915813, "Ignored Group Loot Blade")
    local loggerCfg = h.addon.Options.AddNamespace("Logger", {
        ignoreGroupLoot = false,
        ignoreSelectionThreshold = true,
        loggerLootQualityThreshold = 4,
    })

    loggerCfg:Set("ignoreGroupLoot", true)
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "greed-win-self" then
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    local observedType, parsedLoot = Loot:ObservePassiveLootMessage("greed-win-self", true)
    assertEqual(observedType, nil, "expected Ignore GroupLoot to suppress passive winner recognition")
    assertEqual(parsedLoot, nil, "expected Ignore GroupLoot to suppress parsed passive loot payload")
    assertEqual(Loot:AddGroupLootMessage("greed-win-self"), nil, "expected Ignore GroupLoot to suppress group loot message capture")
    assertEqual(Loot:AddPassiveLootRoll(91, 45000), nil, "expected Ignore GroupLoot to suppress passive roll capture")
end)

test("loot service logger quality override filters below selected threshold", function()
    local h = newHarness()
    local rareLink = h.registerItem(915814, "Rare Logger Blade", 3)
    local epicLink = h.registerItem(915815, "Epic Logger Blade", 4)
    local loggerCfg = h.addon.Options.AddNamespace("Logger", {
        ignoreGroupLoot = false,
        ignoreSelectionThreshold = true,
        loggerLootQualityThreshold = 4,
    })
    loggerCfg:Set("ignoreSelectionThreshold", true)
    loggerCfg:Set("loggerLootQualityThreshold", 4)
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetLootThreshold = function()
        return 0
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "rare-loot-self" then
            return rareLink
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "epic-loot-self" then
            return epicLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:AddLoot("rare-loot-self")
    Raid:AddLoot("epic-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected configured Epic logger threshold to skip rare loot")
    assertEqual(raid.loot[1].itemId, 915815, "expected configured Epic logger threshold to keep epic loot")
end)

test("loot service uses raid threshold when logger override is disabled", function()
    local h = newHarness()
    local rareLink = h.registerItem(915816, "Raid Threshold Rare", 3)
    local loggerCfg = h.addon.Options.AddNamespace("Logger", {
        ignoreGroupLoot = false,
        ignoreSelectionThreshold = true,
        loggerLootQualityThreshold = 4,
    })
    loggerCfg:Set("ignoreSelectionThreshold", false)
    loggerCfg:Set("loggerLootQualityThreshold", 4)
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetLootThreshold = function()
        return 3
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "rare-loot-self" then
            return rareLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:AddLoot("rare-loot-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected disabled logger override to keep loot allowed by raid threshold")
    assertEqual(raid.loot[1].itemId, 915816, "expected disabled logger override to ignore configured Epic threshold")
end)

test("passive group loot failed winner parse is reused when logging normal loot", function()
    local h = newHarness()
    local link = h.registerItem(915811, "Receipt Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end

    local winnerPatternCalls = 0
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "loot-receive-self" then
            winnerPatternCalls = winnerPatternCalls + 1
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Loot = h.addon.Services.Loot

    local observedType = Loot:GetGroupLootMessageResult("loot-receive-self")
    assertEqual(observedType, nil, "expected normal loot receipt to avoid passive winner classification")
    Loot:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected normal receipt to be logged")
    assertEqual(winnerPatternCalls, 1, "expected failed passive winner parse to be reused by AddLoot")
end)

test("passive group loot roll burst skips boss context capture", function()
    local h = newHarness()
    local firstLink = h.registerItem(91582, "Burst Context Blade")
    local secondLink = h.registerItem(91583, "Burst Context Ring")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, name = "Sapphiron", time = 990 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 91 then
            return firstLink
        elseif rollId == 92 then
            return secondLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local Loot = h.addon.Services.Loot

    local contextResolves = 0
    local sessionContexts = {}
    Raid.FindAndRememberBossContextForLootSession = function(_, raidNum, sessionId, options)
        contextResolves = contextResolves + 1
        sessionContexts[sessionId] = {
            raidNum = raidNum,
            bossNid = 10,
            ttlSeconds = options and options.ttlSeconds,
        }
        return 10
    end
    Raid.SetBossContextForLootSession = function(_, raidNum, sessionId, bossNid, ttlSeconds)
        sessionContexts[sessionId] = {
            raidNum = raidNum,
            bossNid = bossNid,
            ttlSeconds = ttlSeconds,
        }
        return bossNid
    end

    local first = Loot:AddPassiveLootRoll(91, 45000)
    local second = Loot:AddPassiveLootRoll(92, 45000)

    assertEqual(contextResolves, 0, "expected passive rolls to avoid boss-context resolution")
    assertEqual(first.bossNid, nil, "expected first passive roll to stay source-light")
    assertEqual(second.bossNid, nil, "expected second passive roll to stay source-light")
    assertEqual(sessionContexts[first.sessionId], nil, "expected first roll session to avoid remembered boss context")
    assertEqual(sessionContexts[second.sessionId], nil, "expected second roll session to avoid remembered boss context")
end)

test("passive group loot need greed and disenchant skip loot counter count calls", function()
    local h = newHarness()
    local link = h.registerItem(91584, "Counter Skip Blade")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self" then
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local Loot = h.addon.Services.Loot

    local countCalls = 0
    local ensureRaidPlayerNid = Raid.EnsureRaidPlayerNid
    Raid.EnsureRaidPlayerNid = function(...)
        return ensureRaidPlayerNid(...)
    end
    Raid.AddPlayerCountForRollType = function()
        countCalls = countCalls + 1
    end

    local observedType, parsedLoot = Loot:GetGroupLootMessageResult("need-win-self")
    assertEqual(observedType, "winner", "expected passive need winner to be observed")
    Loot:AddLoot("need-win-self", nil, nil, parsedLoot)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected passive need winner to still be logged")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected passive need winner to keep NE roll type")
    assertEqual(countCalls, 0, "expected uncounted passive group-loot roll types to avoid LootCounter count calls")
end)

local function newGroupLootSourceResolverHarness(itemId, itemName, rollId, message, sourceData, unitNames)
    local h = newHarness()
    local link = h.registerItem(itemId, itemName)

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    if type(unitNames) == "table" then
        h.addon.UnitIterator = function()
            local index = 0
            return function()
                index = index + 1
                if unitNames[index] then
                    return "raid" .. index
                end
                return nil
            end
        end
        _G.UnitIsConnected = function()
            return true
        end
        _G.UnitName = function(unit)
            if unit == "player" then
                return unitNames[1]
            end
            local index = tonumber(tostring(unit or ""):match("^raid(%d+)$"))
            return index and unitNames[index] or nil
        end
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(activeRollId)
        if activeRollId == rollId then
            return link
        end
        return nil
    end
    local deformatWinners = {
        [message] = {
            rollId = rollId,
            rollValue = 88,
            itemLink = link,
        },
    }
    h._deformatWinners = deformatWinners
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED then
            local entry = deformatWinners[msg]
            if entry then
                return entry.rollId, entry.rollValue, entry.itemLink
            end
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.addon.LootSources._SetDataForTests({
        [itemId] = sourceData,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local resolverCalls = {}
    local findSource = h.addon.LootSources.FindSource
    h.addon.LootSources.FindSource = function(activeItemId, context)
        local raid = h.Database.EnsureRaidById(1)
        resolverCalls[#resolverCalls + 1] = {
            itemId = activeItemId,
            context = context,
            bossKillCountBeforeResolver = raid and #raid.bossKills or nil,
        }
        return findSource(activeItemId, context)
    end

    return h, h.addon.Services.Raid, h.addon.Services.Loot, resolverCalls
end

test("group loot source resolver attributes passive boss item from static source", function()
    local h, Raid, Loot, resolverCalls = newGroupLootSourceResolverHarness(91730, "Resolver Boss Blade", 301, "resolver-boss-win", {
        {
            npcId = 15953,
            npcName = "Grand Widow Faerlina",
            raid = "Naxxramas",
            kind = "boss",
        },
    })

    Raid:AddPassiveLootRoll(301, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-boss-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-boss-win")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#resolverCalls, 1, "expected passive group loot to use the static item source resolver")
    assertEqual(#raid.bossKills, 1, "expected passive group loot to create the static source boss")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected static source boss name")
    assertEqual(#raid.loot, 1, "expected boss item to create one loot row")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected passive loot row to bind the static source boss")
    assertTrue(type(raid.loot[1].lootSource) == "table", "expected passive loot row to persist static source provenance")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected passive loot source kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Grand Widow Faerlina", "expected passive loot source name")
    assertEqual(raid.loot[1].lootSource.sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected passive loot source key")
    assertEqual(raid.loot[1].rollType, h.rollTypes.GREED, "expected passive loot row to keep roll type")
    assertEqual(raid.loot[1].rollValue, 88, "expected passive loot row to keep roll score")
end)

test("group loot source resolver does not create boss attendees from static loot attribution", function()
    local h, Raid, Loot = newGroupLootSourceResolverHarness(91736, "Resolver Attendance Charm", 307, "resolver-attendance-win", {
        {
            npcId = 15953,
            npcName = "Grand Widow Faerlina",
            raid = "Naxxramas",
            kind = "boss",
        },
    }, { "Alice", "Bob" })

    Raid:AddPassiveLootRoll(307, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-attendance-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-attendance-win")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected passive group loot to create the static source boss")
    assertEqual(#(raid.bossKills[1].players or {}), 0, "expected static loot source records to avoid boss attendance snapshots")
end)

test("group loot source resolver prefers static source over recent boss context", function()
    local h, Raid, Loot, resolverCalls = newGroupLootSourceResolverHarness(91734, "Resolver Conflict Blade", 305, "resolver-conflict-win", {
        {
            npcId = 15953,
            npcName = "Grand Widow Faerlina",
            raid = "Naxxramas",
            kind = "boss",
        },
    })
    local currentTime = 1000
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end

    local raid = h.Database.EnsureRaidById(1)
    raid.bossKills = {
        { bossNid = 10, name = "Sapphiron", time = 990 },
    }
    raid.nextBossNid = 11
    h.feature.raidState.lootContext = {
        eventBoss = {
            raidNum = 1,
            bossNid = 10,
            name = "Sapphiron",
            source = "UNIT_DIED",
            seenAt = currentTime,
        },
    }
    h.Database.SetLastBoss(nil)

    Raid:AddPassiveLootRoll(305, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-conflict-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-conflict-win")

    raid = h.Database.EnsureRaidById(1)
    assertEqual(#resolverCalls, 1, "expected passive group loot to use the static item source resolver")
    assertEqual(#raid.bossKills, 2, "expected passive group loot to add the static source boss")
    assertEqual(raid.bossKills[1].name, "Sapphiron", "expected stale context boss to stay intact")
    assertEqual(raid.bossKills[2].name, "Grand Widow Faerlina", "expected static source boss to be added separately")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[2].bossNid, "expected passive loot row to avoid stale recent boss binding")
    assertTrue(type(raid.loot[1].lootSource) == "table", "expected passive loot row to persist static source provenance")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected passive loot source kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Grand Widow Faerlina", "expected passive loot source name")
end)

test("group loot source resolver attributes passive trash item from static source", function()
    local h, Raid, Loot, resolverCalls = newGroupLootSourceResolverHarness(91731, "Resolver Trash Relic", 302, "resolver-trash-win", {
        {
            npcId = 15989,
            npcName = "Naxxramas Cultist",
            raid = "Naxxramas",
            kind = "trash",
        },
    })

    Raid:AddPassiveLootRoll(302, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-trash-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-trash-win")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#resolverCalls, 1, "expected passive group loot to use the static item source resolver")
    assertEqual(#raid.bossKills, 1, "expected passive group loot to create the static trash source")
    assertEqual(raid.bossKills[1].name, "Naxxramas Cultist", "expected static trash source name")
    assertEqual(raid.bossKills[1].sourceKind, "trash", "expected static trash source kind")
    assertEqual(h.Database.GetLastBoss(), nil, "expected named trash source not to become lastBoss")
    assertEqual(#raid.loot, 1, "expected trash item to create one loot row")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[1].bossNid, "expected passive loot row to bind the static trash source")
    assertTrue(type(raid.loot[1].lootSource) == "table", "expected passive loot row to persist static source provenance")
    assertEqual(raid.loot[1].lootSource.kind, "trash", "expected passive loot source kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Naxxramas Cultist", "expected passive loot source name")
end)

test("group loot source resolver records shared static source for passive item", function()
    local ambiguousSourceData = {
        {
            npcId = 15953,
            npcName = "Grand Widow Faerlina",
            raid = "Naxxramas",
            kind = "boss",
        },
        {
            npcId = 15954,
            npcName = "Noth the Plaguebringer",
            raid = "Naxxramas",
            kind = "boss",
        },
    }
    local h, Raid, Loot, resolverCalls = newGroupLootSourceResolverHarness(91732, "Resolver Ambiguous Charm", 303, "resolver-ambiguous-win", ambiguousSourceData)
    local currentTime = 1000
    local ambiguousLink = h.registerItem(91732, "Resolver Ambiguous Charm")
    local staleBossLink = h.registerItem(91733, "Resolver Stale Boss Blade")

    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootRollItemLink = function(activeRollId)
        if activeRollId == 303 then
            return ambiguousLink
        elseif activeRollId == 304 then
            return staleBossLink
        end
        return nil
    end
    h._deformatWinners["resolver-stale-boss-win"] = {
        rollId = 304,
        rollValue = 88,
        itemLink = staleBossLink,
    }
    h.addon.LootSources._SetDataForTests({
        [91732] = ambiguousSourceData,
        [91733] = {
            {
                npcId = 15953,
                npcName = "Grand Widow Faerlina",
                raid = "Naxxramas",
                kind = "boss",
            },
        },
    })

    Raid:AddPassiveLootRoll(304, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-stale-boss-win"), "winner", "expected stale boss seed winner message")
    Raid:AddLoot("resolver-stale-boss-win")
    currentTime = 1040
    Raid:AddPassiveLootRoll(303, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-ambiguous-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-ambiguous-win")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#resolverCalls, 2, "expected passive group loot to resolve both static source items")
    assertEqual(#raid.bossKills, 2, "expected passive group loot to create static source records")
    assertEqual(#raid.loot, 2, "expected seed and ambiguous item sources to create loot rows")
    assertEqual(raid.bossKills[2].name, "Shared", "expected passive shared source boss record to use the compact label")
    assertEqual(raid.loot[2].bossNid, raid.bossKills[2].bossNid, "expected passive shared loot row to bind the shared source")
    assertTrue(type(raid.loot[2].lootSource) == "table", "expected passive shared loot row to persist source provenance")
    assertEqual(raid.loot[2].lootSource.kind, "shared", "expected passive shared loot source kind")
    assertEqual(raid.loot[2].lootSource.sourceName, "Shared", "expected passive shared source label")
    assertTextContains(raid.loot[2].lootSource.sourceKey, "shared|", "expected passive shared source key")
    assertTrue(type(raid.loot[2].lootSource.candidates) == "table", "expected passive shared loot source candidates")
    assertEqual(#raid.loot[2].lootSource.candidates, 2, "expected passive shared loot source to keep both candidates")
    assertEqual(raid.loot[2].lootSource.candidates[1].name, "Grand Widow Faerlina", "expected first passive shared candidate")
    assertEqual(raid.loot[2].lootSource.candidates[1].sourceKey, "naxxramas|boss|15953|grand widow faerlina|any", "expected first passive shared candidate source key")
    assertEqual(raid.loot[2].lootSource.candidates[2].name, "Noth the Plaguebringer", "expected second passive shared candidate")
    assertEqual(raid.loot[2].lootSource.candidates[2].sourceKey, "naxxramas|boss|15954|noth the plaguebringer|any", "expected second passive shared candidate source key")
end)

test("group loot source resolver records shared passive source despite recent context", function()
    local h, Raid, Loot, resolverCalls = newGroupLootSourceResolverHarness(91735, "Resolver Ambiguous Context Charm", 306, "resolver-ambiguous-context-win", {
        {
            npcId = 15953,
            npcName = "Grand Widow Faerlina",
            raid = "Naxxramas",
            kind = "boss",
        },
        {
            npcId = 15954,
            npcName = "Noth the Plaguebringer",
            raid = "Naxxramas",
            kind = "boss",
        },
    })
    local currentTime = 1000
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end

    local raid = h.Database.EnsureRaidById(1)
    raid.bossKills = {
        { bossNid = 10, name = "Grand Widow Faerlina", sourceNpcId = 15953, time = 990 },
    }
    raid.nextBossNid = 11
    h.feature.raidState.bossEventContext = {
        raidNum = 1,
        bossNid = 10,
        name = "Grand Widow Faerlina",
        source = "UNIT_DIED",
        seenAt = currentTime,
    }
    h.Database.SetLastBoss(nil)

    Raid:AddPassiveLootRoll(306, 45000)
    assertEqual(Loot:AddGroupLootMessage("resolver-ambiguous-context-win"), "winner", "expected winner message")
    Raid:AddLoot("resolver-ambiguous-context-win")

    raid = h.Database.EnsureRaidById(1)
    assertEqual(#resolverCalls, 1, "expected passive group loot to use the static item source resolver")
    assertEqual(#raid.bossKills, 2, "expected passive group loot to add a shared static source record")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected recent context boss to stay intact")
    assertEqual(raid.bossKills[2].name, "Shared", "expected passive shared source boss record to use the compact label")
    assertEqual(raid.loot[1].bossNid, raid.bossKills[2].bossNid, "expected passive shared loot row to avoid recent context binding")
    assertTrue(type(raid.loot[1].lootSource) == "table", "expected passive shared loot row to persist source provenance")
    assertEqual(raid.loot[1].lootSource.kind, "shared", "expected passive shared loot source kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Shared", "expected passive shared source label")
    assertTrue(type(raid.loot[1].lootSource.candidates) == "table", "expected passive shared loot source candidates")
    assertEqual(#raid.loot[1].lootSource.candidates, 2, "expected passive shared loot source to keep both candidates")
    assertEqual(raid.loot[1].lootSource.candidates[1].name, "Grand Widow Faerlina", "expected first passive shared candidate")
    assertEqual(raid.loot[1].lootSource.candidates[2].name, "Noth the Plaguebringer", "expected second passive shared candidate")
end)

test("master loot with boss context keeps real source over shared dataset fallback", function()
    local h = newHarness()
    local link = h.registerItem(91737, "Master Shared Context Blade")
    local currentTime = 1000

    h:installRaidStore({
        {
            schemaVersion = 6,
            raidNid = 1,
            zone = "Naxxramas",
            size = 25,
            difficulty = 4,
            players = {},
            bossKills = {
                { bossNid = 10, name = "Sapphiron", time = 990 },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = 10
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "master", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 4
    end
    h.feature.raidState.lootContext = {
        eventBoss = {
            raidNum = 1,
            bossNid = 10,
            name = "Sapphiron",
            source = "UNIT_DIED",
            seenAt = currentTime,
        },
    }
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "master-shared-context-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Raid.lua")
    h.addon.LootSources._SetDataForTests({
        [91737] = {
            { npcId = 15953, npcName = "Grand Widow Faerlina", raid = "Naxxramas", kind = "boss" },
            { npcId = 15954, npcName = "Noth the Plaguebringer", raid = "Naxxramas", kind = "boss" },
        },
    })

    local Raid = h.addon.Services.Raid
    Raid:AddLoot("master-shared-context-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected master loot to avoid creating a shared static source when boss context exists")
    assertEqual(raid.loot[1].bossNid, 10, "expected master loot to stay attached to the real boss context")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected master loot provenance to keep the real boss source kind")
    assertEqual(raid.loot[1].lootSource.sourceName, "Sapphiron", "expected master loot provenance to keep the real boss source name")
end)

test("group loot trash rolls do not inherit previous boss death context", function()
    local h = newHarness()
    local bossLink = h.registerItem(91710, "Group Boss Blade")
    local trashLink = h.registerItem(91711, "Group Trash Cloak")
    local currentTime = 1000
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"
    local trashGuid = "Creature-0-0-0-0-15989-0000000000"

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 101 then
            return bossLink
        end
        if rollId == 102 then
            return trashLink
        end
        return nil
    end
    _G.bit = {
        band = function()
            return 0
        end,
    }
    _G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == bossGuid then
            return 15953
        end
        if guid == trashGuid then
            return 15989
        end
        return 0
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "boss-greed-win-self" then
            return 101, 88, bossLink
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "trash-greed-win-self" then
            return 102, 77, trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, bossGuid, "Grand Widow Faerlina", 0)
    Raid:AddPassiveLootRoll(101, 45000)
    assertEqual(Raid:AddGroupLootMessage("boss-greed-win-self"), "winner", "expected boss group loot winner to be recognized")
    Raid:AddLoot("boss-greed-win-self")

    currentTime = 1005
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005, "UNIT_DIED", nil, nil, 0, trashGuid, "Naxxramas Cultist", 0)
    Raid:AddPassiveLootRoll(102, 45000)
    assertEqual(Raid:AddGroupLootMessage("trash-greed-win-self"), "winner", "expected trash group loot winner to be recognized")
    Raid:AddLoot("trash-greed-win-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 2, "expected boss and trash group loot rows")
    assertEqual(raid.loot[1].bossNid, 0, "expected first group loot row to avoid source binding")
    assertEqual(raid.loot[1].lootSource, nil, "expected first group loot row to avoid source provenance")
    assertEqual(#raid.bossKills, 1, "expected passive trash group loot to avoid creating a TrashMob bucket")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected boss death record to stay intact")
    assertEqual(raid.loot[2].bossNid, 0, "expected trash group loot row to avoid source binding")
    assertEqual(raid.loot[2].lootSource, nil, "expected trash group loot row to avoid source provenance")
end)

test("trash UNIT_DIED context throttles repeated trash updates", function()
    local h = newHarness()
    local currentTime = 1000
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"
    local trashGuidA = "Creature-0-0-0-0-15989-0000000001"
    local trashGuidB = "Creature-0-0-0-0-15990-0000000002"
    local trashGuidC = "Creature-0-0-0-0-15991-0000000003"

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.bit = {
        band = function()
            return 0
        end,
    }
    _G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == bossGuid then
            return 15953
        end
        if guid == trashGuidA then
            return 15989
        end
        if guid == trashGuidB then
            return 15990
        end
        if guid == trashGuidC then
            return 15991
        end
        return 0
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local function getRecentDeathContext()
        return h.feature.raidState.lootContext and h.feature.raidState.lootContext.recentDeath or nil
    end

    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, bossGuid, "Grand Widow Faerlina", 0)

    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, trashGuidA, "Trash A", 0)
    assertEqual(getRecentDeathContext().sourceName, "Trash A", "expected first trash death to seed recent context")

    currentTime = 1000.25
    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, trashGuidB, "Trash B", 0)
    assertEqual(getRecentDeathContext().sourceName, "Trash A", "expected rapid trash deaths to reuse recent context")

    currentTime = 1001.1
    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, trashGuidC, "Trash C", 0)
    assertEqual(getRecentDeathContext().sourceName, "Trash C", "expected throttle window expiry to refresh trash context")

    currentTime = 1001.2
    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, bossGuid, "Grand Widow Faerlina", 0)
    assertEqual(getRecentDeathContext().kind, "boss", "expected boss death to replace trash context")

    currentTime = 1001.3
    Raid:COMBAT_LOG_EVENT_UNFILTERED(currentTime, "UNIT_DIED", nil, nil, 0, trashGuidB, "Trash B", 0)
    assertEqual(getRecentDeathContext().kind, "trash", "expected trash after boss to bypass the previous trash throttle")
    assertEqual(getRecentDeathContext().sourceName, "Trash B", "expected post-boss trash death to refresh context immediately")
end)

local function newRecentDeathContextHarness()
    local h = newHarness()
    local trashLink = h.registerItem(91740, "Recent Trash Cloak")
    local currentTime = 1000
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"
    local trashGuid = "Creature-0-0-0-0-15989-0000000000"

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    h.addon.State.lastBoss = nil
    h.feature.Time.GetCurrentTime = function()
        return currentTime
    end
    _G.GetTime = function()
        return currentTime
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetInstanceInfo = function()
        return "Naxxramas", "raid", 3
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 240 then
            return trashLink
        end
        return nil
    end
    _G.bit = {
        band = function()
            return 0
        end,
    }
    _G.COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400

    h.addon.BossIDs = {
        BossIDs = {
            [15953] = true,
        },
    }
    h.addon.GetCreatureId = function(guid)
        if guid == bossGuid then
            return 15953
        end
        if guid == trashGuid then
            return 15989
        end
        return 0
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "recent-trash-greed-win-self" then
            return 240, 77, trashLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    return {
        h = h,
        Raid = h.addon.Services.Raid,
        setTime = function(value)
            currentTime = value
        end,
        bossGuid = bossGuid,
        trashGuid = trashGuid,
    }
end

test("trash UNIT_DIED without recent boss context is ignored", function()
    local ctx = newRecentDeathContextHarness()
    local Raid = ctx.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)

    assertEqual(ctx.h.feature.raidState.recentLootDeathContext, nil, "expected irrelevant trash death to avoid seeding recent context")
    assertEqual(#ctx.h.Database.EnsureRaidById(1).bossKills, 0, "expected irrelevant trash death to avoid creating boss kills")
end)

test("trash UNIT_DIED after expired boss context is ignored", function()
    local ctx = newRecentDeathContextHarness()
    local Raid = ctx.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, ctx.bossGuid, "Grand Widow Faerlina", 0)
    ctx.setTime(1031)
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1031, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)

    local recent = ctx.h.feature.raidState.recentLootDeathContext
    assertTrue(recent == nil or recent.kind ~= "trash", "expected trash death after expired boss context to avoid seeding trash context")
    assertEqual(#ctx.h.Database.EnsureRaidById(1).bossKills, 1, "expected expired boss context check to avoid creating TrashMob")
end)

test("recent trash death is ignored by lightweight passive group loot", function()
    local ctx = newRecentDeathContextHarness()
    local Raid = ctx.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, ctx.bossGuid, "Grand Widow Faerlina", 0)
    ctx.setTime(1005)
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)
    ctx.setTime(1010)

    Raid:AddPassiveLootRoll(240, 45000)
    local windowContext = ctx.h.feature.raidState.lootWindowBossContext
    assertEqual(windowContext, nil, "expected passive group loot to avoid creating loot-window context")
    assertEqual(Raid:AddGroupLootMessage("recent-trash-greed-win-self"), "winner", "expected trash group loot winner to be recognized")
    Raid:AddLoot("recent-trash-greed-win-self")

    local raid = ctx.h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected one recent trash group-loot row")
    assertEqual(#raid.bossKills, 1, "expected passive group loot to avoid creating a TrashMob bucket")
    assertEqual(raid.loot[1].bossNid, 0, "expected recent trash passive loot to avoid source binding")
    assertEqual(raid.loot[1].lootSource, nil, "expected recent trash passive loot to avoid source provenance")
end)

test("trash burst context is ignored by lightweight passive group loot", function()
    local ctx = newRecentDeathContextHarness()
    local Raid = ctx.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, ctx.bossGuid, "Grand Widow Faerlina", 0)
    ctx.setTime(1005)
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)
    ctx.setTime(1005.5)
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005.5, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)
    ctx.setTime(1013.2)

    Raid:AddPassiveLootRoll(240, 45000)
    assertEqual(Raid:AddGroupLootMessage("recent-trash-greed-win-self"), "winner", "expected throttled burst winner to be recognized")
    Raid:AddLoot("recent-trash-greed-win-self")

    local raid = ctx.h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected one throttled burst group-loot row")
    assertEqual(#raid.bossKills, 1, "expected passive group loot to avoid creating a TrashMob bucket")
    assertEqual(raid.loot[1].bossNid, 0, "expected throttled burst passive loot to avoid source binding")
    assertEqual(raid.loot[1].lootSource, nil, "expected throttled burst passive loot to avoid source provenance")
end)

test("recent trash expiry does not restore source binding for lightweight passive group loot", function()
    local ctx = newRecentDeathContextHarness()
    local Raid = ctx.Raid

    Raid:COMBAT_LOG_EVENT_UNFILTERED(1000, "UNIT_DIED", nil, nil, 0, ctx.bossGuid, "Grand Widow Faerlina", 0)
    ctx.setTime(1005)
    Raid:COMBAT_LOG_EVENT_UNFILTERED(1005, "UNIT_DIED", nil, nil, 0, ctx.trashGuid, "Naxxramas Cultist", 0)
    ctx.setTime(1014)

    Raid:AddPassiveLootRoll(240, 45000)
    assertEqual(Raid:AddGroupLootMessage("recent-trash-greed-win-self"), "winner", "expected delayed group loot winner to be recognized")
    Raid:AddLoot("recent-trash-greed-win-self")

    local raid = ctx.h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected one delayed group-loot row")
    assertEqual(#raid.bossKills, 1, "expected expired recent trash context to avoid creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 0, "expected delayed passive loot to avoid source binding")
    assertEqual(raid.loot[1].lootSource, nil, "expected delayed passive loot to avoid source provenance")
end)

test("group loot winner messages log passive GR history directly", function()
    local h = newHarness()
    local link = h.registerItem(9160, "Greedblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "needbeforegreed", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "greed-win-self" then
            return 91, 88, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddGroupLootMessage("greed-win-self"), "winner", "expected self greed winner message to be recognized")
    Raid:AddLoot("greed-win-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected self winner message to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.GREED, "expected self winner message to classify the loot as GR")
    assertEqual(raid.loot[1].rollValue, 88, "expected self winner message to preserve the greed roll value")
end)

test("group loot logger skips green gem and recipe drops", function()
    local h = newHarness()
    local greenLink = h.registerItem(91720, "Green Disenchant Blade", 2)
    local gemLink = h.registerItem(91721, "Blue Raid Gem", 3)
    local recipeLink = h.registerItem(91722, "Epic Raid Recipe", 4)
    local keepLink = h.registerItem(91723, "Blue Raid Boots", 3)
    local itemClasses = {
        [91720] = "Armor",
        [91721] = "Gem",
        [91722] = "Recipe",
        [91723] = "Armor",
    }

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {},
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 1,
            nextLootNid = 1,
        },
    })
    h.addon.State.currentRaid = 1
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 201 then
            return greenLink
        end
        if rollId == 202 then
            return gemLink
        end
        if rollId == 203 then
            return recipeLink
        end
        if rollId == 204 then
            return keepLink
        end
        return nil
    end

    local oldGetItemInfo = _G.GetItemInfo
    _G.GetItemInfo = function(value)
        local itemName, itemLink, itemRarity, _, _, _, _, _, _, itemTexture = oldGetItemInfo(value)
        local itemId = h.addon.Item.GetItemIdFromLink(itemLink or value)
        return itemName, itemLink, itemRarity, nil, nil, itemClasses[itemId], nil, nil, nil, itemTexture
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "green-win-self" then
            return 201, 41, greenLink
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "gem-win-self" then
            return 202, 42, gemLink
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "recipe-win-self" then
            return 203, 43, recipeLink
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_GREED and msg == "keep-win-self" then
            return 204, 88, keepLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    Raid:AddPassiveLootRoll(201, 45000)
    Raid:AddGroupLootMessage("green-win-self")
    Raid:AddLoot("green-win-self")

    Raid:AddPassiveLootRoll(202, 45000)
    Raid:AddGroupLootMessage("gem-win-self")
    Raid:AddLoot("gem-win-self")

    Raid:AddPassiveLootRoll(203, 45000)
    Raid:AddGroupLootMessage("recipe-win-self")
    Raid:AddLoot("recipe-win-self")

    Raid:AddPassiveLootRoll(204, 45000)
    Raid:AddGroupLootMessage("keep-win-self")
    Raid:AddLoot("keep-win-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected group loot logger to skip green gem and recipe drops")
    assertEqual(raid.loot[1].itemId, 91723, "expected group loot logger to keep normal blue equipment")
    assertEqual(raid.loot[1].rollValue, 88, "expected kept group loot to retain roll metadata")
end)

test("group loot direct winner logs suppress later duplicate loot receipts", function()
    local h = newHarness()
    local link = h.registerItem(9161, "Needblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self" then
            return 77, 96, link
        end
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("need-win-self"), "winner", "expected direct need winner to be recognized")

    Raid:AddLoot("need-win-self")
    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected later duplicate loot receipt to be suppressed after direct winner logging")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected direct winner log to preserve the need type")
    assertEqual(raid.loot[1].rollValue, 96, "expected direct winner log to preserve the numeric roll value")
end)

test("group loot self roll lines preserve rollValue on direct passive winners", function()
    local h = newHarness()
    local link = h.registerItem(9162, "SelfNeedblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_ROLLED_NEED_SELF and msg == "need-roll-self-96" then
            return 96, link
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self-no-value" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("need-roll-self-96"), "selection", "expected self roll line to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("need-win-self-no-value"), "winner", "expected direct winner without numeric payload to be recognized")

    Raid:AddLoot("need-win-self-no-value")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected self direct winner to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected self roll line to preserve the need type")
    assertEqual(raid.loot[1].rollValue, 96, "expected self roll line to preserve the numeric roll value")
end)

test("late self roll lines backfill rollValue on already logged passive winners", function()
    local h = newHarness()
    local link = h.registerItem(9163, "BackfillNeedblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end

    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self-late-roll" then
            return link
        end
        if pattern == _G.LOOT_ROLL_ROLLED_NEED_SELF and msg == "need-roll-self-late-96" then
            return 96, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("need-win-self-late-roll"), "winner", "expected direct winner without numeric payload to be recognized")
    Raid:AddLoot("need-win-self-late-roll")

    assertEqual(Raid:AddGroupLootMessage("need-roll-self-late-96"), "selection", "expected late self roll line to be observed")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected backfill flow to keep a single loot entry")
    assertEqual(raid.loot[1].rollValue, 96, "expected late self roll line to backfill the missing roll value")
end)

test("loot service resolves stored looter through current query facade", function()
    local h = newHarness()
    local link = h.registerItem(9164, "FacadeBackfillNeedblade")
    local newQueries = {
        ResolveLootLooterName = function(self, _raid, loot)
            return (loot and loot.targetLooter) or "TargetRaider"
        end,
    }
    local queryCalls = 0

    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 1
    end

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 7, name = "LegacyTarget", countMS = 0 },
            },
            bossKills = {},
            loot = {
                {
                    lootNid = 1,
                    itemId = 9164,
                    itemName = "FacadeBackfillNeedblade",
                    itemLink = link,
                    itemString = h.addon.Item.GetItemStringFromLink(link),
                    itemCount = 1,
                    looterNid = 55,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 0,
                    rollSessionId = "GL:19",
                    bossNid = 0,
                    time = 1000,
                    source = "CHAT_MSG_LOOT",
                    targetLooter = "TargetRaider",
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 1,
            nextLootNid = 2,
        },
    })

    h:load("!KRT/Services/Loot.lua")

    h.Database.GetRaidQueriesOrNil = function()
        queryCalls = queryCalls + 1
        return newQueries
    end

    h.addon.Services.Raid = {
        GetPlayerName = function()
            return nil
        end,
    }

    local Loot = h.addon.Services.Loot
    local loot = h.Database.EnsureRaidById(1)
    local before = #loot.loot

    local result = Loot:UpgradeLoggedPassiveLootRoll(link, "TargetRaider", h.rollTypes.NEED, 77, "GL:19")

    local after = #loot.loot
    assertTrue(result == true, "expected the existing passive row to be upgraded through query facade resolution")
    assertTrue(queryCalls == 1, "expected current query facade to be called once")
    assertEqual(before, after, "expected existing row to be updated without duplicating")
    assertEqual(loot.loot[1].rollType, h.rollTypes.NEED, "expected roll type to be updated during backfill")
    assertEqual(loot.loot[1].rollValue, 77, "expected roll value to be backfilled")
end)

test("group loot raw need and won messages log passive NE history", function()
    local h = newHarness()
    local link = h.registerItem(9170, "Sabatons")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function()
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddGroupLootMessage("You have selected Need for: " .. link), "selection", "expected raw need selection message to queue passive history")

    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected raw win message to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected raw need selection to classify the loot as NE")
end)

test("raw winner messages do not poison later duplicate passive receipts", function()
    local h = newHarness()
    local link = h.registerItem(9171, "Duplicate Sabatons")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function()
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("You have selected Need for: " .. link), "selection", "expected first raw need selection to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("You won: " .. link), "winner", "expected first raw winner message to be observed")
    Raid:AddLoot("You won: " .. link)

    assertEqual(Raid:AddGroupLootMessage("You have selected Need for: " .. link), "selection", "expected second raw need selection to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("You won: " .. link), "winner", "expected second raw winner message to be observed")
    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 2, "expected duplicate raw win messages to create two loot entries")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected first duplicate raw win to keep NE type")
    assertEqual(raid.loot[2].rollType, h.rollTypes.NEED, "expected second duplicate raw win to keep NE type")
end)

test("item link parser ignores non-string values", function()
    local h = newHarness()

    h:load("!KRT/Modules/Item.lua")

    assertEqual(h.addon.Item.GetItemIdFromLink({}), nil, "expected non-string item refs to be ignored instead of reaching LibDeformat")
    assertEqual(h.addon.Item.GetItemIdFromLink(39718), 39718, "expected numeric item ids to pass through unchanged")
end)

test("item info request returns cached items immediately", function()
    local h = newHarness()
    local link = h.registerItem(39718, "Lost Jewel")
    local callbackCount = 0
    local received

    h:load("!KRT/Modules/Item.lua")

    local handle = h.addon.Item.RequestItemInfo(link, function(snapshot, ok)
        callbackCount = callbackCount + 1
        received = snapshot
        assertTrue(ok == true, "expected cached item request to report success")
    end)

    assertEqual(callbackCount, 1, "expected cached item callback to run immediately")
    assertEqual(received.itemId, 39718, "expected cached item id")
    assertEqual(received.itemName, "Lost Jewel", "expected cached item name")
    assertEqual(handle:IsCancelled(), true, "expected immediate request handle to be inert")
    assertEqual(h.timerCount(), 0, "expected cached item request to avoid scheduling")
end)

test("item info request warms uncached items and resolves on retry", function()
    local h = newHarness()
    local calls = 0
    local warmed = {}
    local callbackCount = 0
    local received

    _G.GetItemInfo = function(value)
        calls = calls + 1
        if calls < 3 then
            return nil
        end
        return "Delayed Jewel", "|cffa335ee|Hitem:40123:0:0:0:0:0:0:0|h[Delayed Jewel]|h|r", 4, nil, nil, nil, nil, nil, nil, "icon"
    end
    _G.GameTooltip = nil
    _G.KRT_ItemTooltip = nil
    _G.CreateFrame = function(_, name)
        local frame = h.makeFrame(true, name)
        frame.SetOwner = function() end
        frame.ClearLines = function() end
        frame.Hide = function() end
        frame.SetHyperlink = function(_, itemLink)
            warmed[#warmed + 1] = itemLink
        end
        if name then
            _G[name] = frame
        end
        return frame
    end

    h:load("!KRT/Modules/Item.lua")

    local handle = h.addon.Item.RequestItemInfo(40123, function(snapshot, ok)
        callbackCount = callbackCount + 1
        received = snapshot
        assertTrue(ok == true, "expected delayed item request to report success")
    end)

    assertEqual(h.timerCount(), 1, "expected uncached item request to schedule one poller")
    assertEqual(#warmed, 1, "expected uncached item request to warm item data")

    h:flushTimers()

    assertEqual(callbackCount, 1, "expected delayed item callback after retry")
    assertEqual(received.itemId, 40123, "expected delayed item id")
    assertEqual(received.itemName, "Delayed Jewel", "expected delayed item name")
    assertEqual(handle:IsCancelled(), true, "expected resolved request to become cancelled")
    assertEqual(h.timerCount(), 0, "expected item request poller to stop after resolution")
end)

test("item info requests for the same uncached item coalesce callbacks", function()
    local h = newHarness()
    local calls = 0
    local warmed = {}
    local resolved = false
    local callbacks = {}

    _G.GetItemInfo = function(value)
        calls = calls + 1
        if not resolved then
            return nil
        end
        local itemId = tonumber(tostring(value or ""):match("item:(%d+)")) or value
        if tonumber(itemId) == 40123 then
            return "Delayed Jewel", "|cffa335ee|Hitem:40123:0:0:0:0:0:0:0|h[Delayed Jewel]|h|r", 4, nil, nil, nil, nil, nil, nil, "icon"
        end
        return nil
    end
    _G.GameTooltip = nil
    _G.KRT_ItemTooltip = nil
    _G.CreateFrame = function(_, name)
        local frame = h.makeFrame(true, name)
        frame.SetOwner = function() end
        frame.ClearLines = function() end
        frame.Hide = function() end
        frame.SetHyperlink = function(_, itemLink)
            warmed[#warmed + 1] = itemLink
        end
        if name then
            _G[name] = frame
        end
        return frame
    end

    h:load("!KRT/Modules/Item.lua")

    local first = h.addon.Item.RequestItemInfo(40123, function(snapshot, ok)
        callbacks[#callbacks + 1] = { snapshot = snapshot, ok = ok }
    end)
    local second = h.addon.Item.RequestItemInfo("|cffa335ee|Hitem:40123:0:0:0:0:0:0:0|h[Delayed Jewel]|h|r", function(snapshot, ok)
        callbacks[#callbacks + 1] = { snapshot = snapshot, ok = ok }
    end)

    assertEqual(calls, 2, "expected joined item request to avoid a duplicate GetItemInfo probe")
    assertEqual(#warmed, 1, "expected joined item request to avoid a duplicate tooltip warm")
    assertEqual(h.timerCount(), 1, "expected coalesced item request to schedule one poller")

    local metrics = h.addon.Item.GetInfoMetrics()
    assertEqual(metrics.requestsStarted, 1, "expected one physical item-info request")
    assertEqual(metrics.requestsJoined, 1, "expected second same-item request to join the pending request")
    assertEqual(metrics.pendingRequests, 1, "expected one pending item-info request")
    assertEqual(metrics.pendingCallbacks, 2, "expected both callbacks to wait on the same request")
    assertEqual(metrics.getItemInfoCalls, 2, "expected metrics to count the initial item-info probes")
    assertEqual(metrics.tooltipProbes, 1, "expected metrics to count the initial tooltip probe")

    resolved = true
    h:flushTimers()

    assertEqual(#callbacks, 2, "expected both joined item-info callbacks to run")
    assertTrue(callbacks[1].ok == true and callbacks[2].ok == true, "expected both joined callbacks to report success")
    assertEqual(callbacks[1].snapshot.itemId, 40123, "expected first joined callback to receive the resolved item")
    assertEqual(callbacks[2].snapshot.itemId, 40123, "expected second joined callback to receive the resolved item")
    assertEqual(first:IsCancelled(), true, "expected first joined handle to be complete")
    assertEqual(second:IsCancelled(), true, "expected second joined handle to be complete")
    assertEqual(h.timerCount(), 0, "expected coalesced item request poller to stop after resolution")

    metrics = h.addon.Item.GetInfoMetrics()
    assertEqual(metrics.requestsCompleted, 1, "expected one coalesced request completion")
    assertEqual(metrics.callbacks, 2, "expected metrics to count both joined callbacks")
    assertEqual(metrics.pendingRequests, 0, "expected no pending item-info requests after resolution")
    assertEqual(metrics.pendingCallbacks, 0, "expected no pending item-info callbacks after resolution")
    assertEqual(metrics.getItemInfoCalls, 3, "expected metrics to count initial probes and one resolving retry")
    assertEqual(metrics.tooltipProbes, 1, "expected resolving retry not to warm the tooltip again")
end)

test("item info request can be cancelled before retry", function()
    local h = newHarness()
    local callbackCount = 0

    _G.GetItemInfo = function()
        return nil
    end

    h:load("!KRT/Modules/Item.lua")

    local handle = h.addon.Item.RequestItemInfo(49999, function()
        callbackCount = callbackCount + 1
    end)
    assertEqual(handle:Cancel(), true, "expected pending item request to cancel")

    h:flushTimers()

    assertEqual(callbackCount, 0, "expected cancelled item request to suppress callback")
    assertEqual(h.timerCount(), 0, "expected cancelled item request to drain poller")
end)

test("loot selection refreshes current item when async item cache resolves", function()
    local h = newHarness()
    local link = "|cffa335ee|Hitem:1401:0:0:0:0:0:0:0|h[Async Master Blade]|h|r"
    local views = {}
    local itemResolved = false

    _G.GetItemInfo = function(value)
        if not itemResolved then
            return nil
        end
        local itemId = tonumber(tostring(value or ""):match("item:(%d+)")) or value
        if tonumber(itemId) == 1401 then
            return "Async Master Blade", link, 4, nil, nil, nil, nil, nil, nil, "Icon1401"
        end
        return nil
    end

    h.Bus.RegisterCallback(h.addon.Events.Internal.SetItem, function(_, itemLink, itemData)
        views[#views + 1] = {
            itemLink = itemLink,
            itemName = itemData and itemData.itemName,
            itemTexture = itemData and itemData.itemTexture,
            itemRarity = itemData and itemData.itemRarity,
        }
    end)

    h:load("!KRT/Modules/Item.lua")
    h.feature.Item = h.addon.Item
    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    h.feature.lootState.fromInventory = true
    Loot:AddItem(link, 1)
    Loot:PrepareItem()

    assertEqual(views[1].itemTexture, "fallback-icon", "expected initial current item view to use fallback icon")
    assertEqual(h.timerCount(), 1, "expected missing current item info to schedule async cache polling")

    itemResolved = true
    h:flushTimers()

    assertEqual(h.timerCount(), 0, "expected async current item cache polling to drain")
    assertEqual(#views, 2, "expected current item view to refresh after async cache resolves")
    assertEqual(views[2].itemName, "Async Master Blade", "expected refreshed current item name")
    assertEqual(views[2].itemTexture, "Icon1401", "expected refreshed current item icon")
    assertEqual(views[2].itemRarity, 4, "expected refreshed current item rarity")
end)

test("reserve list clear edit and spam actions follow state contract", function()
    local h = newHarness()
    local hasData = false
    local displayList = {}
    local clearCount = 0
    local raidMemberCount = 0
    local uiCalls = {}
    local announcements = {}
    local popupCalls = {}
    local registeredApis = {}
    local tooltipBindings = {}

    h.addon.L.BtnClear = "Clear"
    h.addon.L.BtnEdit = "Edit"
    h.addon.L.BtnImport = "Import"
    h.addon.L.BtnQueryItem = "Query Item"
    h.addon.L.BtnClose = "Close"
    h.addon.L.BtnSpamSoftResWhisper = "Spam SR"
    h.addon.L.StrReserveListAcceptSR = "Accept SR"
    h.addon.L.StrReserveListResponseWisp = "Response Wisp"
    h.addon.L.StrReserveListWhisperHelp = "Whisper ML +sr to see reserves.\n" .. "Whisper ML +sr [itemLink] to add one."
    h.addon.L.StrReserveListAcceptSRTooltipTitle = "Accept SR"
    h.addon.L.StrReserveListAcceptSRTooltipText = "Allows players to whisper +sr [itemLink] or +softres [itemLink] to add a reserve. This changes local reserve data."
    h.addon.L.StrReserveListResponseWispTooltipTitle = "Response Wisp"
    h.addon.L.StrReserveListResponseWispTooltipText = "Allows players to whisper +sr or +softres to receive their current reserves. This does not change reserve data."
    h.addon.L.StrReserveListStatus = "Players: %d - Reserved Players: %d"
    h.addon.L.ChatSoftResWhisperHelpQuery = "SoftRes: To see your reserves /w %s +sr or /w %s +softres"
    h.addon.L.ChatSoftResWhisperHelpAdd = "SoftRes: To add one with /w %s +sr [item link] or /w %s +softres [item link]"
    h.addon.L.StrConfirmClearReserves = "Clear all saved loot reserve data?"
    h.addon.L.StrRaidReserves = "KRT : Loot Reserve"
    _G.UnitName = function(unit)
        return unit == "player" and "Masterlooter" or nil
    end
    _G.GetNumRaidMembers = function()
        return raidMemberCount
    end
    _G.UnitInRaid = function()
        return nil
    end

    h.addon.Services.Reserves = {
        HasData = function()
            return hasData
        end,
        ClearSavedReserves = function()
            clearCount = clearCount + 1
            return true
        end,
        GetDisplayList = function()
            return displayList
        end,
        QueryMissingItems = function()
            return false, 0
        end,
    }
    h.addon.Services.Chat = {
        Announce = function(_, message, channel)
            announcements[#announcements + 1] = {
                message = message,
                channel = channel,
            }
            return true
        end,
    }

    h.addon.UI.Frames.GetRef = function(frame, suffix)
        local name = frame and frame.GetName and frame:GetName() or nil
        return name and _G[name .. suffix] or nil
    end

    h.addon.UI.Widgets.Register = function(name, api)
        registeredApis[name] = api
    end
    h.addon.UI.Widgets.Call = function(name, methodName, ...)
        uiCalls[#uiCalls + 1] = {
            name = name,
            methodName = methodName,
        }
        local api = registeredApis[name]
        if api and api[methodName] then
            return api[methodName](...)
        end
        return nil
    end
    h.addon.UI.Popups.ShowConfirm = function(key, text, onAccept, cancels, options)
        popupCalls[#popupCalls + 1] = {
            key = key,
            text = text,
            onAccept = onAccept,
            cancels = cancels,
            options = options,
        }
        return true
    end
    h.addon.UI.Tooltips.Bind = function(frame, text, anchor, title)
        tooltipBindings[#tooltipBindings + 1] = {
            frame = frame,
            text = text,
            anchor = anchor,
            title = title,
        }
        frame:SetScript("OnEnter", function() end)
        frame:SetScript("OnLeave", function() end)
    end

    h.addon.UI.Scaffold.DefineModule = function(cfg)
        local module = cfg.module
        local uiState = h.addon.UI.Scaffold.EnsureModuleState(module)

        function module:BindUI()
            if uiState.Bound then
                return self.frame, self.refs
            end

            local frame = cfg.getFrame()
            uiState.FrameName = frame and frame:GetName() or uiState.FrameName
            uiState.Loaded = uiState.FrameName ~= nil
            self.frame = frame
            self.refs = cfg.acquireRefs and cfg.acquireRefs(frame, uiState.FrameName) or {}

            if cfg.bind then
                cfg.bind(uiState.FrameName, frame, self.refs)
            end
            if cfg.localize then
                cfg.localize(uiState.FrameName, frame, self.refs)
                uiState.Localized = true
            end

            uiState.Bound = true
            return self.frame, self.refs
        end

        function module:EnsureUI()
            if not uiState.Bound then
                self:BindUI()
            end
            return self.frame
        end

        function module:RequestRefresh(reason)
            self:EnsureUI()
            uiState.Dirty = true
            uiState.Reason = reason
            if cfg.refresh then
                return cfg.refresh(uiState.FrameName, self.frame, self.refs, true, reason)
            end
            return nil
        end

        function module:Toggle()
            local frame = self:EnsureUI()
            if not frame then
                return nil
            end
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
            return frame:IsShown()
        end

        function module:Hide()
            local frame = self:EnsureUI()
            if frame then
                frame:Hide()
            end
        end
    end

    local frame = h.makeFrame(true, "KRTReserveListFrame")
    local scrollFrame = h.makeFrame(true, "KRTReserveListFrameScrollFrame")
    local scrollChild = h.makeFrame(true, "KRTReserveListFrameScrollChild")
    local clearButton = h.makeFrame(true, "KRTReserveListFrameClearBtn")
    local editButton = h.makeFrame(true, "KRTReserveListFrameEditButton")
    local queryButton = h.makeFrame(true, "KRTReserveListFrameQueryButton")
    local whisperHelpButton = h.makeFrame(true, "KRTReserveListFrameWhisperHelpButton")
    local softResHelpText = h.makeFrame(true, "KRTReserveListFrameSoftResHelpText")
    local softResStatusText = h.makeFrame(true, "KRTReserveListFrameSoftResStatusText")
    local softResAcceptCheck = h.makeFrame(true, "KRTReserveListFrameSoftResAccept")
    local softResResponseWispCheck = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWisp")
    local softResAcceptLabel = h.makeFrame(true, "KRTReserveListFrameSoftResAcceptStr")
    local responseWispLabel = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWispStr")
    local function setGetChecked(widget)
        return function()
            return widget and widget._krtChecked == true and 1 or nil
        end
    end
    local function setSetChecked(widget)
        return function(_, value)
            widget._krtChecked = value == true or value == 1
        end
    end
    local function setClick(widget)
        return function()
            if widget.OnClick then
                widget:OnClick("LeftButton")
            end
        end
    end
    softResAcceptCheck._krtChecked = false
    softResResponseWispCheck._krtChecked = false
    softResAcceptCheck.GetChecked = setGetChecked(softResAcceptCheck)
    softResResponseWispCheck.GetChecked = setGetChecked(softResResponseWispCheck)
    softResAcceptCheck.SetChecked = setSetChecked(softResAcceptCheck)
    softResResponseWispCheck.SetChecked = setSetChecked(softResResponseWispCheck)
    softResAcceptCheck.Click = setClick(softResAcceptCheck)
    softResResponseWispCheck.Click = setClick(softResResponseWispCheck)

    scrollFrame.ScrollChild = scrollChild
    scrollFrame.SetVerticalScroll = function(self, value)
        self._verticalScroll = value
    end
    frame.ScrollFrame = scrollFrame
    _G.KRTReserveListFrame = frame
    _G.KRTReserveListFrameScrollFrame = scrollFrame
    _G.KRTReserveListFrameScrollChild = scrollChild
    _G.KRTReserveListFrameClearBtn = clearButton
    _G.KRTReserveListFrameEditButton = editButton
    _G.KRTReserveListFrameQueryButton = queryButton
    _G.KRTReserveListFrameWhisperHelpButton = whisperHelpButton
    _G.KRTReserveListFrameSoftResHelpText = softResHelpText
    _G.KRTReserveListFrameSoftResStatusText = softResStatusText
    _G.KRTReserveListFrameSoftResAccept = softResAcceptCheck
    _G.KRTReserveListFrameSoftResResponseWisp = softResResponseWispCheck
    _G.KRTReserveListFrameSoftResAcceptStr = softResAcceptLabel
    _G.KRTReserveListFrameSoftResResponseWispStr = responseWispLabel

    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    setHarnessOption(h, "Reserves", "softResWhisperReplies", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    h:load("!KRT/Widgets/ReservesUI.lua")
    local module = h.addon.Widgets.ReservesUI

    module:RequestRefresh("empty")

    assertEqual(clearButton:GetText(), "Clear", "expected clear action label when no data")
    assertTrue(clearButton:IsEnabled() == false or clearButton:IsShown() == false, "expected clear action hidden or disabled with no data")
    assertEqual(editButton:GetText(), "Edit", "expected edit action to be labeled Edit")
    assertEqual(editButton:IsEnabled(), false, "expected edit action to stay disabled with no data")
    assertEqual(whisperHelpButton:GetText(), "Spam SR", "expected footer action to advertise SoftRes whispers")
    assertTrue(softResHelpText ~= nil, "expected softres help text control stub")
    assertTrue(softResStatusText ~= nil, "expected softres status text control stub")
    assertTrue(softResAcceptCheck ~= nil, "expected accept SR option checkbox stub")
    assertTrue(softResResponseWispCheck ~= nil, "expected Response Wisp checkbox stub")
    assertTrue(softResAcceptLabel ~= nil, "expected Accept SR label")
    assertTrue(responseWispLabel ~= nil, "expected Response Wisp label")
    assertEqual(softResHelpText:GetText(), h.addon.L.StrReserveListWhisperHelp, "expected reserve whisper help text")
    assertEqual(softResStatusText:GetText(), "Players: 0 - Reserved Players: 0", "expected softres status line for empty data")
    assertEqual(softResAcceptLabel:GetText(), "Accept SR", "expected Accept SR label")
    assertEqual(responseWispLabel:GetText(), "Response Wisp", "expected Response Wisp label")
    assertEqual(tooltipBindings[1].frame, softResAcceptCheck, "expected accept SR tooltip binding")
    assertEqual(tooltipBindings[1].anchor, "ANCHOR_RIGHT", "expected accept SR tooltip anchor")
    assertEqual(tooltipBindings[1].title, h.addon.L.StrReserveListAcceptSRTooltipTitle, "expected accept SR tooltip title")
    assertEqual(tooltipBindings[1].text, h.addon.L.StrReserveListAcceptSRTooltipText, "expected accept SR tooltip text")
    assertEqual(tooltipBindings[2].frame, softResResponseWispCheck, "expected response Wisp tooltip binding")
    assertEqual(tooltipBindings[2].anchor, "ANCHOR_RIGHT", "expected response Wisp tooltip anchor")
    assertEqual(tooltipBindings[2].title, h.addon.L.StrReserveListResponseWispTooltipTitle, "expected response Wisp tooltip title")
    assertEqual(tooltipBindings[2].text, h.addon.L.StrReserveListResponseWispTooltipText, "expected response Wisp tooltip text")
    assertEqual(softResAcceptCheck:GetChecked(), nil, "expected add whisper option default false")
    assertEqual(softResResponseWispCheck:GetChecked(), nil, "expected replies option default false")
    softResAcceptCheck:SetChecked(true)
    softResAcceptCheck:Click()
    softResResponseWispCheck:SetChecked(false)
    softResResponseWispCheck:Click()
    assertEqual(getHarnessOption(h, "Reserves", "softResWhisperAdds"), true, "expected accept SR option to persist")
    assertTrue(getHarnessOption(h, "Reserves", "softResWhisperReplies") ~= true, "expected response whisper option to stay disabled")
    softResResponseWispCheck:SetChecked(1)
    softResResponseWispCheck:Click()
    assertEqual(getHarnessOption(h, "Reserves", "softResWhisperReplies"), true, "expected numeric checkbox state to persist")

    clearButton.OnClick(clearButton)
    whisperHelpButton.OnClick(whisperHelpButton)
    if editButton.OnClick then
        editButton.OnClick(editButton)
    end

    assertEqual(#uiCalls, 0, "expected no import action with clear/edit controls")
    assertEqual(#announcements, 0, "expected SoftRes whisper help button to stay silent outside raid")
    assertEqual(softResStatusText:GetText(), "Players: 0 - Reserved Players: 0", "expected softres status line to stay zero with no data")

    raidMemberCount = 10
    module:RequestRefresh("status_counts")
    whisperHelpButton.OnClick(whisperHelpButton)

    assertEqual(#announcements, 2, "expected SoftRes whisper help button to announce two lines")
    assertEqual(softResStatusText:GetText(), "Players: 10 - Reserved Players: 0", "expected status line to show raid size with no reserves")
    assertEqual(softResAcceptCheck:IsEnabled(), true, "expected add whisper checkbox available")
    assertEqual(softResResponseWispCheck:IsEnabled(), true, "expected response whisper checkbox available")
    assertEqual(announcements[1].channel, "RAID", "expected SoftRes whisper help to use raid chat")
    assertEqual(announcements[2].channel, "RAID", "expected SoftRes add help to use raid chat")
    local expectedSoftResQuery = "SoftRes: To see your reserves /w Masterlooter +sr or /w Masterlooter +softres"
    local expectedSoftResAdd = "SoftRes: To add one with /w Masterlooter +sr [item link] or /w Masterlooter +softres [item link]"
    assertEqual(announcements[1].message, expectedSoftResQuery, "expected SoftRes help to include reserve query commands")
    assertEqual(announcements[2].message, expectedSoftResAdd, "expected SoftRes help to include reserve add commands")
    assertEqual(clearCount, 0, "expected empty reserves action not to clear saved data")
    assertEqual(editButton:IsEnabled(), false, "expected edit action to remain disabled with no data")

    hasData = true
    uiCalls = {}
    module:RequestRefresh("has_data")

    assertEqual(clearButton:GetText(), "Clear", "expected data reserves action to clear reserves")
    assertTrue(clearButton:IsShown(), "expected clear reserves button to stay visible when data exists")
    assertTrue(clearButton:IsEnabled(), "expected clear action to be enabled with data")
    assertEqual(editButton:GetText(), "Edit", "expected edit action label to stay Edit with data")
    assertEqual(editButton:IsEnabled(), true, "expected edit action to enable with data")
    displayList = {
        {
            itemId = 1201,
            players = { { name = "Alice" }, { name = "Bob" } },
        },
        {
            itemId = 1202,
            players = { { name = "Alice" } },
        },
    }
    hasData = true
    module:RequestRefresh("status_counts")
    assertEqual(softResStatusText:GetText(), "Players: 10 - Reserved Players: 2", "expected reserve status count from non-empty display list")

    editButton.OnClick(editButton)
    assertEqual(editButton:GetText(), "Edit", "expected edit toggle to keep the Edit label while active")
    assertEqual(editButton._krtReserveEditMode, true, "expected edit action to toggle edit mode on")
    editButton.OnClick(editButton)
    assertEqual(editButton._krtReserveEditMode, false, "expected edit action to toggle edit mode off")

    clearButton.OnClick(clearButton)

    assertEqual(#popupCalls, 1, "expected clear action to request confirmation when data exists")
    assertEqual(popupCalls[1].key, "KRT_RESERVES_CLEAR_SAVED", "expected clear confirmation popup key")
    assertEqual(popupCalls[1].text, h.addon.L.StrConfirmClearReserves, "expected clear confirmation popup text")
    assertEqual(popupCalls[1].options.button1, h.addon.L.BtnClear, "expected confirmation button to stay clear")
    assertEqual(popupCalls[1].options.button2, h.addon.L.BtnCancel, "expected confirmation cancel button to be present")
    assertEqual(clearCount, 0, "expected data reserves action to wait for confirmation")
    assertEqual(type(popupCalls[1].onAccept), "function", "expected confirm callback to be a function")
    if type(popupCalls[1].onAccept) == "function" then
        popupCalls[1].onAccept()
    end
    assertEqual(clearCount, 1, "expected data reserves action to clear saved data after confirmation")
    assertEqual(#uiCalls, 0, "expected data reserves action not to open import")
    assertEqual(editButton:IsEnabled(), true, "expected edit action to stay available until refreshed data changes")
end)

test("reserves ui edit actions commit and remove through service APIs", function()
    local h = newHarness()
    local setQuantityCount = 0
    local removeCount = 0
    local popupCalls = {}

    local frame = h.makeFrame(true, "KRTReserveListFrame")
    local scrollFrame = h.makeFrame(true, "KRTReserveListFrameScrollFrame")
    local scrollChild = h.makeFrame(true, "KRTReserveListFrameScrollChild")
    local clearButton = h.makeFrame(true, "KRTReserveListFrameClearBtn")
    local editButton = h.makeFrame(true, "KRTReserveListFrameEditButton")
    local queryButton = h.makeFrame(true, "KRTReserveListFrameQueryButton")
    local whisperHelpButton = h.makeFrame(true, "KRTReserveListFrameWhisperHelpButton")
    local softResHelpText = h.makeFrame(true, "KRTReserveListFrameSoftResHelpText")
    local softResAcceptCheck = h.makeFrame(true, "KRTReserveListFrameSoftResAccept")
    local softResResponseWispCheck = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWisp")
    local softResAcceptLabel = h.makeFrame(true, "KRTReserveListFrameSoftResAcceptStr")
    local responseWispLabel = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWispStr")

    local rowName = "KRTReserveListFrameReserveRow1"
    local secondRowName = "KRTReserveListFrameReserveRow2"
    local headerName = "KRTReserveListFrameReserveHeader1"
    _G[rowName .. "Name"] = h.makeFrame(true, rowName .. "Name")
    _G[rowName .. "Quantity"] = h.makeFrame(true, rowName .. "Quantity")
    _G[rowName .. "QuantityEdit"] = h.makeFrame(true, rowName .. "QuantityEdit")
    _G[rowName .. "RemoveBtn"] = h.makeFrame(true, rowName .. "RemoveBtn")
    _G[secondRowName .. "Name"] = h.makeFrame(true, secondRowName .. "Name")
    _G[secondRowName .. "Quantity"] = h.makeFrame(true, secondRowName .. "Quantity")
    _G[secondRowName .. "QuantityEdit"] = h.makeFrame(true, secondRowName .. "QuantityEdit")
    _G[secondRowName .. "RemoveBtn"] = h.makeFrame(true, secondRowName .. "RemoveBtn")
    _G[headerName .. "CollapseButton"] = h.makeFrame(true, headerName .. "CollapseButton")
    if type(_G[headerName .. "CollapseButton"].SetPushedTexture) ~= "function" then
        _G[headerName .. "CollapseButton"].SetPushedTexture = function() end
    end
    if type(_G[headerName .. "CollapseButton"].SetNormalTexture) ~= "function" then
        _G[headerName .. "CollapseButton"].SetNormalTexture = function() end
    end

    scrollFrame.ScrollChild = scrollChild
    scrollFrame.SetVerticalScroll = function(self, value)
        self._verticalScroll = value
    end
    frame.ScrollFrame = scrollFrame
    _G.KRTReserveListFrame = frame
    _G.KRTReserveListFrameScrollFrame = scrollFrame
    _G.KRTReserveListFrameScrollChild = scrollChild
    _G.KRTReserveListFrameClearBtn = clearButton
    _G.KRTReserveListFrameEditButton = editButton
    _G.KRTReserveListFrameQueryButton = queryButton
    _G.KRTReserveListFrameWhisperHelpButton = whisperHelpButton
    _G.KRTReserveListFrameSoftResHelpText = softResHelpText
    _G.KRTReserveListFrameSoftResAccept = softResAcceptCheck
    _G.KRTReserveListFrameSoftResResponseWisp = softResResponseWispCheck
    _G.KRTReserveListFrameSoftResAcceptStr = softResAcceptLabel
    _G.KRTReserveListFrameSoftResResponseWispStr = responseWispLabel

    _G.KRT_Reserves = {
        Alice = {
            playerNameDisplay = "Alice",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1201:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", quantity = 2 },
            },
        },
        Bob = {
            playerNameDisplay = "Bob",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1201:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", quantity = 2 },
            },
        },
    }
    h.addon.UI.Widgets.IsEnabled = function()
        return true
    end
    h.addon.L.BtnCancel = "Cancel"
    h.addon.L.BtnDelete = "Delete"
    h.addon.L.BtnSave = "Save"
    h.addon.L.StrConfirmApplyReserveEdits = "Apply %d reserve edit change(s)?"
    h.addon.L.StrConfirmRemoveReserveRow = "Remove reserve for %s on item %s?"
    h.addon.UI.Widgets.IsRegistered = function(widgetId)
        return widgetId == "Reserves"
    end
    local definedConfirmPopups = {}
    h.addon.UI.Popups.IsDefined = function(key)
        return definedConfirmPopups[key] ~= nil
    end
    h.addon.UI.Popups.DefineConfirm = function(key, text, onAccept, cancelId, options)
        definedConfirmPopups[key] = {
            key = key,
            text = text,
            onAccept = onAccept,
            cancelId = cancelId,
            options = options,
        }
        return true
    end
    h.addon.UI.Popups.ShowConfirm = function(key, text, onAccept, cancelId, options)
        if not definedConfirmPopups[key] then
            h.addon.UI.Popups.DefineConfirm(key, text, onAccept, cancelId, options)
        end
        popupCalls[#popupCalls + 1] = definedConfirmPopups[key]
        return true
    end
    local scaffold = h.addon.UI.Scaffold
    local ensureModuleState = scaffold.EnsureModuleState
    if type(ensureModuleState) ~= "function" then
        ensureModuleState = function(module)
            module.__krtUiState = module.__krtUiState or {}
            return module.__krtUiState
        end
        scaffold.EnsureModuleState = ensureModuleState
    end
    scaffold.DefineModule = function(cfg)
        local module = cfg.module
        local uiState = ensureModuleState(module)

        function module:BindUI()
            if uiState.Bound then
                return self.frame, self.refs
            end

            local frame = cfg.getFrame()
            uiState.FrameName = frame and frame.GetName and frame:GetName() or uiState.FrameName
            uiState.Loaded = uiState.FrameName ~= nil
            self.frame = frame
            self.refs = cfg.acquireRefs and cfg.acquireRefs(frame, uiState.FrameName) or {}

            if cfg.bind then
                cfg.bind(uiState.FrameName, frame, self.refs)
            end
            if cfg.localize then
                cfg.localize(uiState.FrameName, frame, self.refs)
                uiState.Localized = true
            end

            uiState.Bound = true
            return self.frame, self.refs
        end

        function module:EnsureUI()
            if not uiState.Bound then
                self:BindUI()
            end
            return self.frame
        end

        function module:RequestRefresh(reason)
            self:EnsureUI()
            uiState.Dirty = true
            uiState.Reason = reason
            if cfg.refresh then
                return cfg.refresh(uiState.FrameName, self.frame, self.refs, true, reason)
            end
            return nil
        end

        function module:Toggle()
            local frame = self:EnsureUI()
            if not frame then
                return nil
            end
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
            return frame:IsShown()
        end

        function module:Hide()
            local frame = self:EnsureUI()
            if frame then
                frame:Hide()
            end
        end
    end
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves
    if Service.Load then
        Service:Load()
    end
    local wrappedSetQuantity = Service.SetPlayerReserveQuantity
    Service.SetPlayerReserveQuantity = function(_, player, itemId, quantity)
        setQuantityCount = setQuantityCount + 1
        return wrappedSetQuantity(Service, player, itemId, quantity)
    end
    local wrappedRemove = Service.RemovePlayerReserve
    Service.RemovePlayerReserve = function(_, player, itemId)
        removeCount = removeCount + 1
        return wrappedRemove(Service, player, itemId)
    end

    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    setHarnessOption(h, "Reserves", "softResWhisperReplies", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    h:load("!KRT/Widgets/ReservesUI.lua")
    local module = h.addon.Widgets.ReservesUI
    module:RequestRefresh("rows")

    local function findReserveRow(playerName)
        local target = playerName and string.lower(tostring(playerName)) or nil
        if not target then
            return nil
        end
        for i = 1, 4 do
            local row = _G["KRTReserveListFrameReserveRow" .. tostring(i)]
            local rowName = row and row._playerName
            if rowName and string.lower(tostring(rowName)) == target then
                return row
            end
        end
        return nil
    end

    local row = findReserveRow("Alice")
    local secondRow = findReserveRow("Bob")
    assertTrue(row ~= nil, "expected Alice reserve row to be rendered")
    assertTrue(secondRow ~= nil, "expected Bob reserve row to be rendered")
    local rowEdit = row.quantityEdit
    local secondRowEdit = secondRow.quantityEdit
    assertTrue(rowEdit ~= nil, "expected reserve edit box to be wired")
    assertTrue(secondRowEdit ~= nil, "expected second reserve edit box to be wired")
    local rowRemove = row.removeButton
    assertTrue(rowRemove ~= nil, "expected reserve remove button to be wired")

    editButton.OnClick(editButton)
    rowEdit:SetText("5")
    rowEdit.OnEnterPressed(rowEdit)
    assertEqual(setQuantityCount, 1, "expected Enter to commit row edit value")

    rowEdit:SetText("9")
    secondRowEdit:SetText("8")
    editButton.OnClick(editButton)
    assertEqual(#popupCalls, 1, "expected edit-off with changed rows to request confirmation")
    assertEqual(popupCalls[1].key, "KRT_RESERVES_APPLY_EDITS", "expected edit confirmation popup key")
    assertEqual(popupCalls[1].text, h.addon.L.StrConfirmApplyReserveEdits:format(2), "expected edit confirmation text")
    assertEqual(popupCalls[1].options.button1, h.addon.L.BtnSave, "expected edit confirmation save button")
    assertEqual(popupCalls[1].options.button2, h.addon.L.BtnCancel, "expected edit confirmation cancel button")
    assertEqual(editButton._krtReserveEditMode, true, "expected edit mode to remain active before acceptance")
    assertEqual(setQuantityCount, 1, "expected edits to wait for confirmation")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].quantity, 5, "expected row edits already accepted via Enter to persist")
    assertEqual(_G.KRT_Reserves.Bob.reserves[1].quantity, 2, "expected edit-off changes for non-enter path to wait for confirmation")
    assertEqual(type(popupCalls[1].onAccept), "function", "expected an accept callback")
    if type(popupCalls[1].onAccept) == "function" then
        popupCalls[1].onAccept()
    end
    assertEqual(setQuantityCount, 3, "expected toggling edit mode off to commit all visible row edit values after acceptance")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].quantity, 9, "expected edit-off commit to persist quantity")
    assertEqual(_G.KRT_Reserves.Bob.reserves[1].quantity, 8, "expected edit-off commit to preserve later row edits across refreshes")
    assertEqual(editButton._krtReserveEditMode, false, "expected edit mode to exit after acceptance")

    popupCalls = {}
    editButton.OnClick(editButton)
    secondRow = findReserveRow("Bob")
    assertTrue(secondRow ~= nil, "expected Bob row after confirmed edit refresh")
    secondRowEdit = secondRow.quantityEdit
    secondRowEdit:SetText("7")
    editButton.OnClick(editButton)
    assertEqual(#popupCalls, 1, "expected second edit-off confirmation to reuse a refreshed popup callback")
    assertEqual(popupCalls[1].text, h.addon.L.StrConfirmApplyReserveEdits:format(1), "expected second edit confirmation text to be refreshed")
    assertEqual(setQuantityCount, 3, "expected second edit-off changes to wait for confirmation")
    popupCalls[1].onAccept()
    assertEqual(setQuantityCount, 4, "expected second edit-off confirmation to apply the current pending edit")
    assertEqual(_G.KRT_Reserves.Bob.reserves[1].quantity, 7, "expected second edit-off confirmation to apply Bob's current value")
    assertEqual(editButton._krtReserveEditMode, false, "expected edit mode to exit after second acceptance")

    popupCalls = {}
    editButton.OnClick(editButton)
    editButton.OnClick(editButton)
    assertEqual(#popupCalls, 0, "expected edit mode off to skip confirmation with no changed edits")
    assertEqual(editButton._krtReserveEditMode, false, "expected edit mode to toggle off when no row edits changed")

    removeCount = 0
    row = findReserveRow("Alice")
    rowRemove = row.removeButton
    rowRemove.OnClick(rowRemove)
    assertEqual(removeCount, 0, "expected remove action inactive while edit mode is off")

    editButton.OnClick(editButton)
    assertEqual(editButton._krtReserveEditMode, true, "expected edit mode to enable before remove confirmation")
    row = findReserveRow("Alice")
    rowEdit = row.quantityEdit
    rowRemove = row.removeButton
    rowEdit:SetText("bad")
    rowEdit.OnEscapePressed(rowEdit)
    assertEqual(rowEdit:GetText(), "9", "expected escape to restore committed row value")
    popupCalls = {}

    rowRemove.OnClick(rowRemove)
    assertEqual(#popupCalls, 1, "expected remove action to request confirmation while edit mode is on")
    assertEqual(popupCalls[1].key, "KRT_RESERVES_REMOVE_ROW", "expected remove confirmation popup key")
    assertEqual(popupCalls[1].text, h.addon.L.StrConfirmRemoveReserveRow:format("Alice", "1201"), "expected remove confirmation text")
    assertEqual(popupCalls[1].options.button1, h.addon.L.BtnDelete, "expected remove confirmation button text")
    assertEqual(popupCalls[1].options.button2, h.addon.L.BtnCancel, "expected remove confirmation cancel text")
    assertEqual(removeCount, 0, "expected remove action to wait for confirmation")
    popupCalls[1].onAccept()
    assertEqual(removeCount, 1, "expected remove action to call service API after confirmation")
    assertEqual(_G.KRT_Reserves.Alice, nil, "expected removal to clear player container for last reserve")
    assertTrue(_G.KRT_Reserves.Bob ~= nil, "expected removing one player reserve to preserve other players")

    popupCalls = {}
    local bobRow = findReserveRow("Bob")
    assertTrue(bobRow ~= nil, "expected Bob row after confirmed Alice remove refresh")
    bobRow.removeButton.OnClick(bobRow.removeButton)
    assertEqual(#popupCalls, 1, "expected second remove confirmation to reuse a refreshed popup callback")
    assertEqual(popupCalls[1].text, h.addon.L.StrConfirmRemoveReserveRow:format("Bob", "1201"), "expected second remove confirmation text to be refreshed")
    assertEqual(removeCount, 1, "expected second remove action to wait for confirmation")
    popupCalls[1].onAccept()
    assertEqual(removeCount, 2, "expected second remove confirmation to remove the current player")
    assertEqual(_G.KRT_Reserves.Bob, nil, "expected refreshed remove confirmation to remove Bob")
end)

test("reserves ui keeps player-name alignment with fixed delete slot", function()
    local h = newHarness()

    local frame = h.makeFrame(true, "KRTReserveListFrame")
    local scrollFrame = h.makeFrame(true, "KRTReserveListFrameScrollFrame")
    local scrollChild = h.makeFrame(true, "KRTReserveListFrameScrollChild")
    local clearButton = h.makeFrame(true, "KRTReserveListFrameClearBtn")
    local editButton = h.makeFrame(true, "KRTReserveListFrameEditButton")
    local queryButton = h.makeFrame(true, "KRTReserveListFrameQueryButton")
    local whisperHelpButton = h.makeFrame(true, "KRTReserveListFrameWhisperHelpButton")
    local softResHelpText = h.makeFrame(true, "KRTReserveListFrameSoftResHelpText")
    local softResAcceptCheck = h.makeFrame(true, "KRTReserveListFrameSoftResAccept")
    local softResResponseWispCheck = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWisp")
    local softResAcceptLabel = h.makeFrame(true, "KRTReserveListFrameSoftResAcceptStr")
    local responseWispLabel = h.makeFrame(true, "KRTReserveListFrameSoftResResponseWispStr")

    local rowName = "KRTReserveListFrameReserveRow1"
    local secondRowName = "KRTReserveListFrameReserveRow2"
    local headerName = "KRTReserveListFrameReserveHeader1"
    _G[rowName .. "Name"] = h.makeFrame(true, rowName .. "Name")
    _G[rowName .. "Quantity"] = h.makeFrame(true, rowName .. "Quantity")
    _G[rowName .. "QuantityEdit"] = h.makeFrame(true, rowName .. "QuantityEdit")
    _G[rowName .. "RemoveBtn"] = h.makeFrame(true, rowName .. "RemoveBtn")
    _G[rowName .. "EditSlot"] = h.makeFrame(true, rowName .. "EditSlot")

    _G[secondRowName .. "Name"] = h.makeFrame(true, secondRowName .. "Name")
    _G[secondRowName .. "Quantity"] = h.makeFrame(true, secondRowName .. "Quantity")
    _G[secondRowName .. "QuantityEdit"] = h.makeFrame(true, secondRowName .. "QuantityEdit")
    _G[secondRowName .. "EditSlot"] = h.makeFrame(true, secondRowName .. "EditSlot")
    _G[headerName .. "CollapseButton"] = h.makeFrame(true, headerName .. "CollapseButton")
    if type(_G[headerName .. "CollapseButton"].SetPushedTexture) ~= "function" then
        _G[headerName .. "CollapseButton"].SetPushedTexture = function() end
    end
    if type(_G[headerName .. "CollapseButton"].SetNormalTexture) ~= "function" then
        _G[headerName .. "CollapseButton"].SetNormalTexture = function() end
    end

    scrollFrame.ScrollChild = scrollChild
    scrollFrame.SetVerticalScroll = function(self, value)
        self._verticalScroll = value
    end
    frame.ScrollFrame = scrollFrame
    _G.KRTReserveListFrame = frame
    _G.KRTReserveListFrameScrollFrame = scrollFrame
    _G.KRTReserveListFrameScrollChild = scrollChild
    _G.KRTReserveListFrameClearBtn = clearButton
    _G.KRTReserveListFrameEditButton = editButton
    _G.KRTReserveListFrameQueryButton = queryButton
    _G.KRTReserveListFrameWhisperHelpButton = whisperHelpButton
    _G.KRTReserveListFrameSoftResHelpText = softResHelpText
    _G.KRTReserveListFrameSoftResAccept = softResAcceptCheck
    _G.KRTReserveListFrameSoftResResponseWisp = softResResponseWispCheck
    _G.KRTReserveListFrameSoftResAcceptStr = softResAcceptLabel
    _G.KRTReserveListFrameSoftResResponseWispStr = responseWispLabel

    _G.KRT_Reserves = {
        Alice = {
            playerNameDisplay = "Alice",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1201:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", quantity = 1 },
            },
        },
        Bob = {
            playerNameDisplay = "Bob",
            reserves = { { rawID = 1202, itemName = "Aged Core Leather", itemLink = "|cff0070dd|Hitem:1202:0:0:0:0:0:0:0|h[Aged Core Leather]|h|r", quantity = 1 } },
        },
    }

    h.addon.UI.Widgets.IsEnabled = function()
        return true
    end
    h.addon.UI.Widgets.IsRegistered = function(widgetId)
        return widgetId == "Reserves"
    end

    local scaffold = h.addon.UI.Scaffold
    local ensureModuleState = scaffold.EnsureModuleState
    if type(ensureModuleState) ~= "function" then
        ensureModuleState = function(module)
            module.__krtUiState = module.__krtUiState or {}
            return module.__krtUiState
        end
        scaffold.EnsureModuleState = ensureModuleState
    end
    scaffold.DefineModule = function(cfg)
        local module = cfg.module
        local uiState = ensureModuleState(module)

        function module:BindUI()
            if uiState.Bound then
                return self.frame, self.refs
            end

            local frame = cfg.getFrame()
            uiState.FrameName = frame and frame.GetName and frame:GetName() or uiState.FrameName
            uiState.Loaded = uiState.FrameName ~= nil
            self.frame = frame
            self.refs = cfg.acquireRefs and cfg.acquireRefs(frame, uiState.FrameName) or {}

            if cfg.bind then
                cfg.bind(uiState.FrameName, frame, self.refs)
            end
            if cfg.localize then
                cfg.localize(uiState.FrameName, frame, self.refs)
                uiState.Localized = true
            end

            uiState.Bound = true
            return self.frame, self.refs
        end

        function module:EnsureUI()
            if not uiState.Bound then
                self:BindUI()
            end
            return self.frame
        end

        function module:RequestRefresh(reason)
            self:EnsureUI()
            uiState.Dirty = true
            uiState.Reason = reason
            if cfg.refresh then
                return cfg.refresh(uiState.FrameName, self.frame, self.refs, true, reason)
            end
            return nil
        end

        function module:Toggle()
            local frame = self:EnsureUI()
            if not frame then
                return nil
            end
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
            return frame:IsShown()
        end

        function module:Hide()
            local frame = self:EnsureUI()
            if frame then
                frame:Hide()
            end
        end
    end

    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Widgets/ReservesUI.lua")
    h.addon.Services.Reserves.GetDisplayList = function()
        return {
            {
                itemId = 1201,
                itemName = "Coldsteel Dagger",
                itemLink = "|cff0070dd|Hitem:1201:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r",
                players = {
                    {
                        name = "Alice",
                        displayName = "Alice",
                        quantity = 1,
                        class = "WARRIOR",
                    },
                },
            },
            {
                itemId = 1202,
                itemName = "Aged Core Leather",
                itemLink = "|cff0070dd|Hitem:1202:0:0:0:0:0:0:0|h[Aged Core Leather]|h|r",
                players = {
                    {
                        name = "Bob",
                        displayName = "Bob",
                        quantity = 1,
                        class = "MAGE",
                    },
                },
            },
        }
    end
    h.addon.Services.Reserves.HasData = function()
        return true
    end

    local module = h.addon.Widgets.ReservesUI
    _G[rowName] = nil
    _G[secondRowName] = nil
    _G[headerName] = nil
    module:RequestRefresh("reserve_edit_slot_rows")

    local function findReserveRow(playerName)
        local target = playerName and string.lower(tostring(playerName)) or nil
        if not target then
            return nil
        end
        for i = 1, 4 do
            local row = _G["KRTReserveListFrameReserveRow" .. tostring(i)]
            local rowName = row and row._playerName
            if rowName and string.lower(tostring(rowName)) == target then
                return row
            end
        end
        return nil
    end

    local aliceRow = findReserveRow("Alice")
    local bobRow = findReserveRow("Bob")
    assertTrue(aliceRow ~= nil, "expected Alice reserve row to be rendered")
    assertTrue(bobRow ~= nil, "expected Bob reserve row to be rendered")
    local aliceNamePoint = aliceRow.nameText._points and aliceRow.nameText._points[1]
    local bobNamePoint = bobRow.nameText._points and bobRow.nameText._points[1]
    assertTrue(aliceNamePoint ~= nil, "expected Alice name point to be set")
    assertTrue(bobNamePoint ~= nil, "expected Bob name point to be set")

    assertTrue(aliceRow.editSlot ~= nil, "expected Alice edit/delete slot to be wired")
    assertTrue(bobRow.editSlot ~= nil, "expected Bob edit/delete slot to be wired")

    editButton.OnClick(editButton)
    assertTrue(aliceRow.removeButton:IsShown(), "expected Alice remove button to show in edit mode")
    editButton.OnClick(editButton)
    local aliceNamePointEdit = aliceRow.nameText._points and aliceRow.nameText._points[1]
    local bobNamePointEdit = bobRow.nameText._points and bobRow.nameText._points[1]
    assertEqual(aliceNamePoint.point, "LEFT", "expected Alice name anchor point to stay stable")
    assertEqual(aliceNamePoint.point, aliceNamePointEdit.point, "expected Alice name anchor point to remain stable across modes")
    assertEqual(aliceNamePoint.x, aliceNamePointEdit.x, "expected Alice name x anchor to remain stable across modes")
    assertEqual(bobNamePoint.point, bobNamePointEdit.point, "expected Bob name anchor point to remain stable across modes")
    assertEqual(bobNamePoint.x, bobNamePointEdit.x, "expected Bob name x anchor to remain stable across modes")
    assertEqual(aliceNamePointEdit.x, bobNamePointEdit.x, "expected reserve row name anchor x to remain fixed without spec icons")
end)

test("reserves import window uses compact mode and format buttons", function()
    local h = newHarness()
    local mode = "multi"
    local parseCalls = {}
    local applyCount = 0
    local registeredApis = {}

    h.addon.Services.Reserves = {
        GetImportMode = function()
            return mode
        end,
        SetImportMode = function(_, nextMode)
            mode = nextMode
        end,
        ParseImport = function(_, text, parseMode, opts)
            parseCalls[#parseCalls + 1] = {
                text = text,
                mode = parseMode,
                format = opts and opts.format or nil,
            }
            return {
                reservesData = {
                    alice = {
                        playerNameDisplay = "Alice",
                        reserves = {
                            { rawID = 1201 },
                        },
                    },
                },
                nPlayers = 1,
            }
        end,
        ApplyImport = function()
            applyCount = applyCount + 1
            return true, 1
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.UI.Widgets.Register = function(name, api)
        registeredApis[name] = api
    end
    h.addon.UI.Scaffold.DefineModule = function(cfg)
        local module = cfg.module
        local uiState = h.addon.UI.Scaffold.EnsureModuleState(module)

        function module:BindUI()
            if uiState.Bound then
                return self.frame, self.refs
            end

            local frame = cfg.getFrame()
            uiState.FrameName = frame and frame:GetName() or uiState.FrameName
            uiState.Loaded = uiState.FrameName ~= nil
            self.frame = frame
            self.refs = cfg.acquireRefs and cfg.acquireRefs(frame, uiState.FrameName) or {}

            if cfg.bind then
                cfg.bind(uiState.FrameName, frame, self.refs)
            end
            if cfg.localize then
                cfg.localize(uiState.FrameName, frame, self.refs)
                uiState.Localized = true
            end

            uiState.Bound = true
            return self.frame, self.refs
        end

        function module:EnsureUI()
            if not uiState.Bound then
                self:BindUI()
            end
            return self.frame
        end

        function module:RequestRefresh(reason)
            self:EnsureUI()
            uiState.Dirty = true
            uiState.Reason = reason
            if cfg.refresh then
                return cfg.refresh(uiState.FrameName, self.frame, self.refs, true, reason)
            end
            return nil
        end

        function module:Hide()
            local frame = self:EnsureUI()
            if frame then
                frame:Hide()
            end
        end

        function module:Toggle()
            local frame = self:EnsureUI()
            if not frame then
                return nil
            end
            if frame:IsShown() then
                frame:Hide()
            else
                frame:Show()
            end
            return frame:IsShown()
        end
    end

    local frame = h.makeFrame(true, "KRTImportWindow")
    local hint = h.makeFrame(true, "KRTImportWindowHint")
    local status = h.makeFrame(true, "KRTImportWindowStatus")
    local modeLabel = h.makeFrame(true, "KRTImportWindowModeLabel")
    local formatLabel = h.makeFrame(true, "KRTImportWindowFormatLabel")
    local editBox = h.makeFrame(true, "KRTImportEditBox")
    local scrollFrame = h.makeFrame(true, "KRTImportScrollFrame")
    local scrollBar = h.makeFrame(true, "KRTImportScrollFrameScrollBar")
    local scrollUpButton = h.makeFrame(true, "KRTImportScrollFrameScrollBarScrollUpButton")
    local scrollDownButton = h.makeFrame(true, "KRTImportScrollFrameScrollBarScrollDownButton")
    local confirmButton = h.makeFrame(true, "KRTImportConfirmButton")
    local cancelButton = h.makeFrame(true, "KRTImportCancelButton")
    local multiButton = h.makeFrame(true, "KRTImportWindowModeMultiButton")
    local plusButton = h.makeFrame(true, "KRTImportWindowModePlusButton")
    local jsonButton = h.makeFrame(true, "KRTImportWindowFormatJsonButton")
    local csvButton = h.makeFrame(true, "KRTImportWindowFormatCsvButton")
    local function makeButtonRegions(name)
        _G[name .. "Left"] = h.makeFrame(true, name .. "Left")
        _G[name .. "Middle"] = h.makeFrame(true, name .. "Middle")
        _G[name .. "Right"] = h.makeFrame(true, name .. "Right")
    end

    _G.KRTImportWindow = frame
    _G.KRTImportWindowHint = hint
    _G.KRTImportWindowStatus = status
    _G.KRTImportWindowModeLabel = modeLabel
    _G.KRTImportWindowFormatLabel = formatLabel
    _G.KRTImportEditBox = editBox
    _G.KRTImportScrollFrame = scrollFrame
    _G.KRTImportScrollFrameScrollBar = scrollBar
    _G.KRTImportScrollFrameScrollBarScrollUpButton = scrollUpButton
    _G.KRTImportScrollFrameScrollBarScrollDownButton = scrollDownButton
    _G.KRTImportConfirmButton = confirmButton
    _G.KRTImportCancelButton = cancelButton
    _G.KRTImportWindowModeMultiButton = multiButton
    _G.KRTImportWindowModePlusButton = plusButton
    _G.KRTImportWindowFormatJsonButton = jsonButton
    _G.KRTImportWindowFormatCsvButton = csvButton
    makeButtonRegions("KRTImportWindowModeMultiButton")
    makeButtonRegions("KRTImportWindowModePlusButton")
    makeButtonRegions("KRTImportWindowFormatJsonButton")
    makeButtonRegions("KRTImportWindowFormatCsvButton")

    h:load("!KRT/Localization/localization.en.lua")
    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    setHarnessOption(h, "Reserves", "softResWhisperReplies", false, {
        softResWhisperAdds = false,
        softResWhisperReplies = false,
    })
    h:load("!KRT/Widgets/ReservesUI.lua")
    local Import = h.addon.Widgets.ReservesUI.Import

    Import:EnsureUI()

    assertEqual(modeLabel:GetText(), "Reserve System", "expected compact import reserve-system label")
    assertEqual(formatLabel:GetText(), "Import Format", "expected compact import format label")
    assertEqual(multiButton:GetText(), "Multi-reserve", "expected compact import mode button text")
    assertEqual(plusButton:GetText(), "Plus System", "expected compact import plus button text")
    assertEqual(jsonButton:GetText(), "JSON", "expected compact import JSON format button text")
    assertEqual(csvButton:GetText(), "CSV", "expected compact import CSV format button text")
    assertEqual(editBox._width, 244, "expected import edit box runtime width to leave a fixed scrollbar gutter")
    assertEqual(scrollFrame._scrollChild, editBox, "expected import edit box to be the explicit scroll child")
    assertEqual(editBox._textInsets and editBox._textInsets[1], 8, "expected import edit box left padding")
    assertEqual(editBox._textInsets and editBox._textInsets[2], 8, "expected import edit box right padding")
    assertEqual(editBox._textInsets and editBox._textInsets[3], 8, "expected import edit box top padding")
    assertEqual(editBox._textInsets and editBox._textInsets[4], 8, "expected import edit box bottom padding")
    assertEqual(editBox._wordWrap, true, "expected import edit box text to wrap inside the paste area")
    assertEqual(scrollBar._points and scrollBar._points[1] and scrollBar._points[1].x, 28, "expected import scrollbar to sit in the right gutter")
    assertEqual(scrollUpButton._points and scrollUpButton._points[1] and scrollUpButton._points[1].x, 28, "expected import scrollbar up button to sit in the right gutter")
    assertEqual(scrollDownButton._points and scrollDownButton._points[1] and scrollDownButton._points[1].x, 28, "expected import scrollbar down button to sit in the right gutter")
    assertTrue(type(multiButton.OnClick) == "function", "expected multi button click handler")
    assertTrue(type(plusButton.OnClick) == "function", "expected plus button click handler")
    assertTrue(type(jsonButton.OnClick) == "function", "expected JSON button click handler")
    assertTrue(type(csvButton.OnClick) == "function", "expected CSV button click handler")
    assertEqual(jsonButton._highlighted, nil, "expected selected JSON format button not to lock highlight")
    assertEqual(csvButton._alpha, nil, "expected unselected CSV format button not to use transparency")
    assertEqual(_G.KRTImportWindowFormatJsonButtonMiddle._vertexColor[1], 1, "expected selected JSON button to keep normal KRT red styling")
    assertEqual(_G.KRTImportWindowFormatCsvButtonMiddle._vertexColor[1], 0.45, "expected unselected CSV button to use a muted red tint")

    plusButton.OnClick(plusButton)
    csvButton.OnClick(csvButton)
    editBox:SetText("csv payload")
    confirmButton.OnClick(confirmButton)

    assertEqual(mode, "plus", "expected plus button to update reserve import mode")
    assertEqual(plusButton._highlighted, nil, "expected selected Plus System button not to lock highlight")
    assertEqual(multiButton._alpha, nil, "expected unselected Multi-reserve button not to use transparency")
    assertEqual(jsonButton._alpha, nil, "expected unselected JSON button not to use transparency")
    assertEqual(_G.KRTImportWindowModeMultiButtonMiddle._vertexColor[1], 0.45, "expected unselected Multi-reserve button to use a muted red tint")
    assertEqual(_G.KRTImportWindowModePlusButtonMiddle._vertexColor[1], 1, "expected selected Plus System button to keep normal KRT red styling")
    assertEqual(_G.KRTImportWindowFormatJsonButtonMiddle._vertexColor[1], 0.45, "expected unselected JSON button to use a muted red tint")
    assertEqual(_G.KRTImportWindowFormatCsvButtonMiddle._vertexColor[1], 1, "expected selected CSV button to keep normal KRT red styling")
    assertEqual(parseCalls[1].mode, "plus", "expected import to pass the selected reserve mode")
    assertEqual(parseCalls[1].format, "csv", "expected import to pass the selected input format")
    assertEqual(parseCalls[1].text, "csv payload", "expected import to read the edit box payload")
    assertEqual(applyCount, 1, "expected successful compact import to apply parsed data")
    assertTrue(registeredApis.Reserves ~= nil, "expected reserves UI API to remain registered")
end)

test("reserves import XML allocates expanded paste area", function()
    local file = assert(io.open("!KRT/UI/Reserves.xml", "r"))
    local xml = file:read("*a")
    file:close()

    assertTrue(xml:find('name="$parentEditBoxPanel"', 1, true) ~= nil, "expected import XML to include a visible paste-area panel")
    assertTrue(xml:find('<AbsDimension x="20" y="-78" />', 1, true) ~= nil, "expected mode buttons to start at the template-B left column")
    assertTrue(xml:find('<AbsDimension x="20" y="-128" />', 1, true) ~= nil, "expected format buttons to start at the template-B left column")
    assertTrue(xml:find('<AbsDimension x="14" y="0" />', 1, true) ~= nil, "expected paired buttons to use the template-B compact column gap")
    assertTrue(xml:find('<AbsDimension x="300" y="130" />', 1, true) ~= nil, "expected import edit box border to exclude the external scrollbar gutter")
    assertTrue(xml:find('<AbsDimension x="0" y="-162" />', 1, true) ~= nil, "expected narrowed edit box panel to match the current mockup center lane")
    assertTrue(xml:find('<AbsDimension x="276" y="114" />', 1, true) ~= nil, "expected import scroll frame to fit inside the shortened edit box panel")
    assertTrue(xml:find('<AbsDimension x="244" y="114" />', 1, true) ~= nil, "expected import edit box text area to stay inside the shortened scroll viewport")
    assertTrue(xml:find('<AbsDimension x="20" y="51" />', 1, true) ~= nil, "expected import status lane to stay visible below the paste area")
end)

test("ui primitives expose pixel-aligned sizing helpers", function()
    local h = newHarness()
    _G.GetCurrentResolution = function()
        return 1
    end
    _G.GetScreenResolutions = function()
        return "1920x1080"
    end

    h:load("!KRT/Modules/UI/Visuals.lua")

    local frame = h.makeFrame(true, "PixelFrame")
    frame.GetEffectiveScale = function()
        return 1
    end
    frame.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
        self._point = { point, relativeTo, relativePoint, x, y }
    end

    h.addon.UI.Primitives.SetPixelSize(frame, 10.2, 10.7, 1, 1)
    h.addon.UI.Primitives.SetPixelPoint(frame, "TOPLEFT", nil, "TOPLEFT", 2.2, -2.2, 1, 1)

    assertTrue(math.abs(frame:GetWidth() - 9.9555555555556) < 0.0000001, "expected width to align to physical pixels")
    assertTrue(math.abs(frame:GetHeight() - 10.666666666667) < 0.0000001, "expected height to align to physical pixels")
    assertTrue(math.abs(frame._point[4] - 2.1333333333333) < 0.0000001, "expected x offset to align to physical pixels")
    assertTrue(math.abs(frame._point[5] + 2.1333333333333) < 0.0000001, "expected y offset to align to physical pixels")
end)

test("ui tooltips render reusable multiline models", function()
    local h = newHarness()
    local owner = h.makeFrame(true, "TooltipOwner")
    local calls = {}
    _G.GameTooltip = {
        SetOwner = function(self, frame, anchor)
            self.owner = frame
            self.anchor = anchor
            calls[#calls + 1] = { kind = "owner", frame = frame, anchor = anchor }
        end,
        AddLine = function(self, text, r, g, b, wrap)
            calls[#calls + 1] = { kind = "line", text = text, r = r, g = g, b = b, wrap = wrap }
        end,
        Show = function(self)
            self.shown = true
            calls[#calls + 1] = { kind = "show" }
        end,
        Hide = function(self)
            self.hidden = true
            calls[#calls + 1] = { kind = "hide" }
        end,
    }

    h:load("!KRT/Modules/UI/Frames.lua")

    local shown = h.addon.UI.Tooltips.ShowLines(owner, {
        title = "Shared",
        titleColor = { 1, 0.82, 0 },
        heading = "Possible sources:",
        lines = { "Grand Widow Faerlina", "Noth the Plaguebringer" },
        anchor = "ANCHOR_CURSOR",
    })

    assertTrue(shown == true, "expected UI tooltip helper to report that it rendered a tooltip")
    assertEqual(_G.GameTooltip.owner, owner, "expected UI tooltip helper to bind the provided owner")
    assertEqual(_G.GameTooltip.anchor, "ANCHOR_CURSOR", "expected UI tooltip helper to use the provided anchor")
    assertEqual(calls[2].text, "Shared", "expected UI tooltip helper to render the title")
    assertEqual(calls[3].text, "Possible sources:", "expected UI tooltip helper to render the heading")
    assertEqual(calls[4].text, "Grand Widow Faerlina", "expected UI tooltip helper to render first detail line")
    assertEqual(calls[5].text, "Noth the Plaguebringer", "expected UI tooltip helper to render second detail line")
    assertTrue(_G.GameTooltip.shown == true, "expected UI tooltip helper to show the tooltip")
end)

test("ui tooltips bind reusable model providers", function()
    local h = newHarness()
    local owner = h.makeFrame(true, "TooltipProviderOwner")
    local calls = {}
    _G.GameTooltip = {
        SetOwner = function(self, frame, anchor)
            self.owner = frame
            self.anchor = anchor
            calls[#calls + 1] = { kind = "owner", frame = frame, anchor = anchor }
        end,
        AddLine = function(self, text, r, g, b, wrap)
            calls[#calls + 1] = { kind = "line", text = text, r = r, g = g, b = b, wrap = wrap }
        end,
        Show = function(self)
            self.shown = true
            calls[#calls + 1] = { kind = "show" }
        end,
        Hide = function(self)
            self.hidden = true
            calls[#calls + 1] = { kind = "hide" }
        end,
    }

    h:load("!KRT/Modules/UI/Frames.lua")

    local providerCalls = 0
    local bound = h.addon.UI.Tooltips.BindModel(owner, function(frame)
        providerCalls = providerCalls + 1
        assertEqual(frame, owner, "expected tooltip provider to receive the bound frame")
        return {
            title = "Shared",
            lines = { "Grand Widow Faerlina" },
        }
    end, "ANCHOR_RIGHT")

    assertTrue(bound == true, "expected UI tooltip helper to bind a model provider")
    owner.OnEnter(owner)

    assertEqual(providerCalls, 1, "expected OnEnter to call the tooltip model provider")
    assertEqual(_G.GameTooltip.owner, owner, "expected provider tooltip to bind the frame")
    assertEqual(_G.GameTooltip.anchor, "ANCHOR_RIGHT", "expected provider tooltip to use the bind anchor")
    assertEqual(calls[2].text, "Shared", "expected provider tooltip to render title")
    assertEqual(calls[3].text, "Grand Widow Faerlina", "expected provider tooltip to render model lines")

    owner.OnLeave(owner)
    assertTrue(_G.GameTooltip.hidden == true, "expected provider tooltip OnLeave to hide")
end)

test("ui scaffold define module keeps bind and refresh lifecycle centralized", function()
    local h = newHarness()
    local frame = h.makeFrame(true, "KRTU1ScaffoldFrame")
    local driver = h.makeFrame(true, "KRTU1ScaffoldRefreshDriver")
    local calls = {}

    _G.KRTU1ScaffoldFrame = frame
    _G.CreateFrame = function()
        return driver
    end

    h:load("!KRT/Modules/UI/Frames.lua")

    local module = {}
    h.addon.UI.Scaffold.DefineModule({
        module = module,
        getFrame = function()
            return frame
        end,
        acquireRefs = function(boundFrame, frameName)
            calls[#calls + 1] = "refs:" .. tostring(frameName)
            assertEqual(boundFrame, frame, "expected acquireRefs to receive the module frame")
            return { Button = true }
        end,
        bind = function(frameName, boundFrame, refs)
            calls[#calls + 1] = "bind:" .. tostring(frameName) .. ":" .. tostring(refs.Button)
            assertEqual(boundFrame, frame, "expected bind to receive the module frame")
        end,
        localize = function(frameName, boundFrame, refs)
            calls[#calls + 1] = "localize:" .. tostring(frameName) .. ":" .. tostring(refs.Button)
            assertEqual(boundFrame, frame, "expected localize to receive the module frame")
        end,
        refresh = function(frameName, boundFrame, refs, dirty, reason)
            calls[#calls + 1] = "refresh:" .. tostring(frameName) .. ":" .. tostring(dirty) .. ":" .. tostring(reason)
            assertEqual(boundFrame, frame, "expected refresh to receive the module frame")
            assertTrue(refs.Button == true, "expected refresh to receive acquired refs")
        end,
    })

    local boundFrame, refs = module:BindUI()

    assertEqual(boundFrame, frame, "expected BindUI to return the module frame")
    assertTrue(refs.Button == true, "expected BindUI to return acquired refs")
    assertEqual(calls[1], "refs:KRTU1ScaffoldFrame", "expected refs before bind")
    assertEqual(calls[2], "bind:KRTU1ScaffoldFrame:true", "expected bind after refs")
    assertEqual(calls[3], "localize:KRTU1ScaffoldFrame:true", "expected localize after bind")
    assertTrue(driver.OnUpdate ~= nil, "expected visible bind to schedule refresh")

    driver.OnUpdate(driver)
    assertEqual(calls[4], "refresh:KRTU1ScaffoldFrame:true:bind", "expected bind refresh")

    module:RequestRefresh("manual")
    assertTrue(driver.OnUpdate ~= nil, "expected manual refresh to schedule driver")
    driver.OnUpdate(driver)
    assertEqual(calls[5], "refresh:KRTU1ScaffoldFrame:true:manual", "expected manual refresh")

    assertEqual(module:EnsureUI(), frame, "expected EnsureUI to reuse bound frame")
    assertEqual(#calls, 5, "expected EnsureUI not to rebind or relocalize")
end)

test("auto loot rules suggest disenchant for enchanting materials", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h:load("!KRT/Services/Loot/Rules.lua")

    local Rules = h.addon.Services.Loot._Rules
    local decision = Rules:GetItemSuggestion({
        itemId = 34057,
        itemLink = "|cffa335ee|Hitem:34057:0:0:0:0:0:0:0|h[Abyss Crystal]|h|r",
        itemRarity = 4,
    })

    assertEqual(decision.action, "disenchant", "expected enchanting materials to suggest DE")
    assertEqual(decision.rollType, h.rollTypes.DISENCHANT, "expected DE suggestion to map to disenchant roll type")
    assertEqual(decision.targetKey, "disenchanter", "expected DE suggestion to target the configured disenchanter")
    assertEqual(decision.reason, "enchanting_material", "expected explicit enchanting material reason")
    assertTrue(decision.automatic ~= true, "expected auto-loot rules to suggest only")
end)

test("auto loot rules keep ignored non-material items as logger skip", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h:load("!KRT/Services/Loot/Rules.lua")

    local Rules = h.addon.Services.Loot._Rules
    local decision = Rules:GetItemSuggestion({
        itemId = 40752,
        itemLink = "|cff0070dd|Hitem:40752:0:0:0:0:0:0:0|h[Emblem of Heroism]|h|r",
        itemRarity = 4,
    })

    assertEqual(decision.action, "skipLogger", "expected ignored non-material items to stay logger-only skips")
    assertEqual(decision.reason, "ignored_item", "expected ignored item reason")
    assertTrue(decision.skipLogger == true, "expected skipLogger flag")
    assertTrue(decision.automatic ~= true, "expected ignored decision to suggest only")
end)

test("auto loot rules suggest bank for quality BoE items", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h:load("!KRT/Services/Loot/Rules.lua")

    local Rules = h.addon.Services.Loot._Rules
    local decision = Rules:GetItemSuggestion({
        itemId = 50000,
        itemLink = "|cffa335ee|Hitem:50000:0:0:0:0:0:0:0|h[BoE Epic]|h|r",
        itemRarity = 4,
        itemBind = 2,
    })

    assertEqual(decision.action, "bank", "expected quality BoE items to suggest Bank")
    assertEqual(decision.rollType, h.rollTypes.BANK, "expected Bank suggestion to map to bank roll type")
    assertEqual(decision.targetKey, "banker", "expected Bank suggestion to target configured banker")
    assertEqual(decision.reason, "boe_quality", "expected BoE quality reason")
    assertTrue(decision.automatic ~= true, "expected BoE decision to suggest only")
end)

test("auto loot rules use tooltip bind data for 3.3.5 BoE items", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h.addon.Item.GetItemBindFromTooltip = function(itemLink)
        if itemLink and itemLink:find("item:39717", 1, true) then
            return 2
        end
        return nil
    end
    _G.GetItemInfo = function()
        return "Inexorable Sabatons", nil, 4, 213
    end
    h:load("!KRT/Services/Loot/Rules.lua")

    local Rules = h.addon.Services.Loot._Rules
    local decision = Rules:GetItemSuggestion({
        itemId = 39717,
        itemLink = "|cffa335ee|Hitem:39717:0:0:0:0:0:0:0|h[Inexorable Sabatons]|h|r",
        itemRarity = 4,
    })

    assertEqual(decision.action, "bank", "expected tooltip-detected BoE items to suggest Bank")
    assertEqual(decision.reason, "boe_quality", "expected tooltip BoE quality reason")
    assertTrue(decision.automatic ~= true, "expected tooltip BoE decision to suggest only")
end)

test("auto loot rules leave normal non-BoE items undecided", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h:load("!KRT/Services/Loot/Rules.lua")

    local Rules = h.addon.Services.Loot._Rules
    local decision = Rules:GetItemSuggestion({
        itemId = 50001,
        itemLink = "|cffa335ee|Hitem:50001:0:0:0:0:0:0:0|h[Boss Epic]|h|r",
        itemRarity = 4,
        itemBind = 1,
    })

    assertEqual(decision.action, "none", "expected normal non-BoE loot to stay undecided")
    assertEqual(decision.rollType, nil, "expected no roll type suggestion")
    assertEqual(decision.targetKey, nil, "expected no assignment target suggestion")
    assertTrue(decision.automatic ~= true, "expected normal decision to suggest only")
end)

test("loot service exposes suggestion-only auto loot decisions for tracked items", function()
    local h = newHarness()
    h:load("!KRT/Modules/Dataset/IgnoredItems.lua")
    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    Loot:AddItem("|cffa335ee|Hitem:34057:0:0:0:0:0:0:0|h[Abyss Crystal]|h|r", 1, "Abyss Crystal", 4, "Icon34057")

    local decision = Loot:GetAutoLootSuggestion(1)

    assertEqual(decision.action, "disenchant", "expected tracked enchanting material to expose DE suggestion")
    assertEqual(decision.rollType, h.rollTypes.DISENCHANT, "expected tracked suggestion to map to DE roll type")
    assertTrue(decision.automatic ~= true, "expected tracked item suggestion to avoid automatic assignment")
end)

test("loot service slot lookup works with method-call syntax and itemId fallback", function()
    local h = newHarness()
    local lootLink = h.registerItem(39718, "Corpse Scarab Handguards")
    local awardLink = "|cff0070dd|Hitem:39718:5:0:0:0:0:0:0|h[Corpse Scarab Handguards]|h|r"

    _G.GetNumLootItems = function()
        return 1
    end
    _G.GetLootSlotLink = function(index)
        if index == 1 then
            return lootLink
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")

    local itemIndex = h.addon.Services.Loot:FindLootSlotIndex(awardLink)

    assertEqual(itemIndex, 1, "expected real Loot service method calls to keep matching the same itemId across hyperlink variants")
end)

test("raid service owns master loot candidate cache resolution", function()
    local h = newHarness()
    local itemLink = h.registerItem(9701, "Candidate Cache Blade")
    local candidates = { "Alice", "Bob" }

    h.addon.GetNumGroupMembers = function()
        return #candidates
    end
    _G.GetMasterLootCandidate = function(index)
        return candidates[index]
    end

    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:FindMasterLootCandidateIndex(itemLink, "Bob"), 2, "expected raid service to resolve the current master loot candidate index")
    assertTrue(Raid:CanResolveMasterLootCandidates(itemLink), "expected raid service to report available master loot candidates")

    candidates = { "Cara" }
    Raid:RequestMasterLootCandidateRefresh()

    assertEqual(Raid:FindMasterLootCandidateIndex(itemLink, "Cara"), 1, "expected raid candidate cache invalidation to force a rebuild")
end)

test("master native raid grid opens for master loot candidates", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob", "Cara" },
        selectedLootQuality = 3,
    })
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()

    local grid = ctx.h.addon.Widgets.RaidGrid
    assertTrue(grid:IsShown(), "expected native grid to show for master loot candidates")
    assertEqual(grid:GetButtonCount(), 3, "expected one grid button per candidate")
end)

test("master debug raid grid opens with fake N-player roster without awarding", function()
    local ctx = setupMasterAwardHarness({
        candidates = {},
        selectedLootQuality = 3,
    })
    loadRaidGridWidget(ctx.h)

    local shownCount = ctx.Master:ShowDebugRaidGrid(25)

    local grid = ctx.h.addon.Widgets.RaidGrid
    assertEqual(shownCount, 25, "expected debug grid to clamp and return the shown fake player count")
    assertTrue(grid:IsShown(), "expected debug grid to show fake players")
    assertEqual(grid:GetMode(), "debug", "expected debug grid mode to avoid live award behavior")
    assertEqual(grid:GetButtonCount(), 25, "expected one debug grid button per fake player")

    assertEqual(grid:ClickButtonForTest(1), false, "expected debug grid clicks to stay display-only")
    assertEqual(#ctx.givenLoot, 0, "expected debug grid not to call GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected debug grid not to queue KRT awards")
end)

test("slash debug raidgrid opens fake Raid Grid", function()
    local ctx = setupMasterAwardHarness({
        candidates = {},
        selectedLootQuality = 3,
    })
    _G.SlashCmdList = {}
    loadRaidGridWidget(ctx.h)
    ctx.h:load("!KRT/Localization/localization.en.lua")
    ctx.h.Database.RequestControllerMethod = function(name, methodName, ...)
        local controller = ctx.h.addon.Controllers[name]
        local method = controller and controller[methodName]
        if type(method) == "function" then
            return method(controller, ...)
        end
        return nil
    end
    ctx.h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("debug raidgrid 12")

    local grid = ctx.h.addon.Widgets.RaidGrid
    assertTrue(grid:IsShown(), "expected slash command to show debug grid")
    assertEqual(grid:GetMode(), "debug", "expected slash command to open debug grid mode")
    assertEqual(grid:GetButtonCount(), 12, "expected slash command count to drive fake player count")
    assertContains(ctx.h.logs.info, "Raid Grid Debug shown with %d fake players.", "expected slash command to report the debug grid flow")
end)

test("master item popup debug fallback uses real roster before fake players", function()
    local ctx = setupMasterAwardHarness({
        candidates = {},
        selectedLootQuality = 3,
    })
    local rosterNames = { "Alice", "Bob" }
    ctx.h.feature.coreState.debug = {
        raidGridTargetCount = 5,
    }
    ctx.h.addon.UnitIterator = function()
        local index = 0
        return function()
            index = index + 1
            if rosterNames[index] then
                return "raid" .. index
            end
            return nil
        end
    end
    _G.UnitName = function(unit)
        local index = tonumber(string.match(tostring(unit or ""), "^raid(%d+)$"))
        return index and rosterNames[index] or nil
    end
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()

    local grid = ctx.h.addon.Widgets.RaidGrid
    assertTrue(grid:IsShown(), "expected item popup to show the debug fallback grid")
    assertEqual(grid:GetMode(), "debug", "expected no-candidate item popup fallback to stay display-only")
    assertEqual(grid:GetButtonCount(), 5, "expected debug fallback to fill real roster up to the target count")
    assertEqual(grid:GetEntryNameForTest(1), "Alice", "expected real roster players first")
    assertEqual(grid:GetEntryNameForTest(2), "Bob", "expected real roster players before fake rows")
    assertEqual(grid:GetEntryNameForTest(3), "Player1", "expected fake players to fill only after real roster")
    assertEqual(grid:ClickButtonForTest(1), false, "expected debug fallback clicks not to award")
    assertEqual(#ctx.givenLoot, 0, "expected debug fallback not to call GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected debug fallback not to queue KRT awards")
end)

test("master native raid grid hides Blizzard dropdown lists", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 3,
    })
    local list1 = ctx.h.makeFrame(true, "DropDownList1")
    local list2 = ctx.h.makeFrame(true, "DropDownList2")
    _G.DropDownList1 = list1
    _G.DropDownList2 = list2
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()
    ctx.h:flushTimers()

    assertTrue(not list1:IsShown(), "expected native grid to hide DropDownList1")
    assertTrue(not list2:IsShown(), "expected native grid to hide DropDownList2")
end)

test("master native raid grid is layered above loot selection frames", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 3,
    })
    _G.LootButton1:SetFrameLevel(42)
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()

    local gridFrame = _G.KRTRaidGridFrame
    assertTrue(gridFrame ~= nil, "expected native grid frame to exist")
    assertEqual(gridFrame:GetFrameStrata(), "FULLSCREEN_DIALOG", "expected native grid to use a strata above loot selection frames")
    assertTrue(gridFrame._toplevel == true, "expected native grid to be a top-level frame")
    assertTrue(gridFrame:GetFrameLevel() > _G.LootButton1:GetFrameLevel(), "expected native grid level to sit above the selected loot button")
end)

test("master native raid grid opens centered on screen", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 3,
    })
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()

    local gridFrame = _G.KRTRaidGridFrame
    local point = gridFrame and gridFrame._points and gridFrame._points[1] or nil
    assertTrue(point ~= nil, "expected native grid to be positioned")
    assertEqual(point.point, "CENTER", "expected native grid to anchor from its center")
    assertEqual(point.relativeTo, _G.UIParent, "expected native grid to anchor to UIParent")
    assertEqual(point.relativePoint, "CENTER", "expected native grid to anchor to screen center")
    assertEqual(point.x, 0, "expected native grid horizontal offset to be zero")
    assertEqual(point.y, 0, "expected native grid vertical offset to be zero")
end)

test("master native raid grid confirms above-threshold manual awards", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 4,
    })
    loadRaidGridWidget(ctx.h)

    ctx.Master:OPEN_MASTER_LOOT_LIST()
    ctx.h.addon.Widgets.RaidGrid:ClickButtonForTest(2)

    assertEqual(#ctx.givenLoot, 0, "expected above-threshold click to wait for confirmation")
    local popup = _G.StaticPopupDialogs.KRT_MASTER_LOOT_GRID_CONFIRM
    assertTrue(popup ~= nil, "expected KRT-owned grid confirmation popup to be defined")
    popup.OnAccept(nil, popup._krtData)

    assertEqual(#ctx.givenLoot, 1, "expected confirmation to award through KRT")
    assertEqual(ctx.givenLoot[1].candidateIndex, 2, "expected confirmation award to resolve the clicked candidate")
    assertEqual(ctx.queuedAwards[1].rollType, ctx.h.rollTypes.MANUAL, "expected manual grid award to use Manual roll type")
end)

test("master target grid updates Hold target without awarding", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice", "Bob" },
        selectedLootQuality = 3,
    })
    local rosterNames = { "Alice", "Bob", "Cara" }
    ctx.h.addon.UnitIterator = function()
        local index = 0
        return function()
            index = index + 1
            if rosterNames[index] then
                return "raid" .. index
            end
            return nil
        end
    end
    _G.UnitName = function(unit)
        local index = tonumber(string.match(tostring(unit or ""), "^raid(%d+)$"))
        return index and rosterNames[index] or nil
    end
    _G.GetRaidRosterInfo = function(index)
        if rosterNames[index] then
            return rosterNames[index], nil, 1
        end
        return nil
    end
    loadRaidGridWidget(ctx.h)

    ctx.Master._Private.OpenAssignmentTargetGrid("holder")
    ctx.h.addon.Widgets.RaidGrid:ClickButtonForTest(3)

    assertEqual(ctx.raid.holder, "Cara", "expected target grid to persist holder")
    assertEqual(ctx.h.feature.lootState.holder, "Cara", "expected target grid to update holder state")
    assertEqual(#ctx.givenLoot, 0, "expected target selection not to award loot")
end)

test("master award matches loot slots by itemId when hyperlinks differ", function()
    local liveLootSlotLink = "|cff0070dd|Hitem:39718:5:0:0:0:0:0:0|h[Corpse Scarab Handguards]|h|r"
    local ctx = setupMasterAwardHarness({
        itemId = 39718,
        itemName = "Corpse Scarab Handguards",
        lootSlotLink = liveLootSlotLink,
        candidates = { "Disonesta" },
        rollsByName = {
            Disonesta = 69,
        },
        model = {
            rows = {
                makeMasterRollRow("Disonesta", 69, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Disonesta", roll = 69 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Disonesta",
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok == true, "expected award flow to succeed when the live loot slot link differs but the itemId matches")
    assertEqual(#ctx.givenLoot, 1, "expected award flow to reach GiveMasterLoot once")
    assertEqual(ctx.givenLoot[1].itemIndex, 1, "expected itemId fallback to resolve the first loot slot")
    assertEqual(ctx.givenLoot[1].candidateIndex, 1, "expected award flow to resolve the candidate index for the winner")
end)

test("master loot award credits loot counter after loot slot clear confirmation", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice" },
        rollsByName = {
            Alice = 88,
        },
        model = {
            rows = {
                makeMasterRollRow("Alice", 88, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 88 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok == true, "expected master loot award to succeed")
    assertEqual(#ctx.givenLoot, 1, "expected award flow to reach GiveMasterLoot once")
    assertEqual(#ctx.addCounts, 0, "expected award flow to wait for loot slot confirmation before crediting LootCounter")

    ctx.Master:LOOT_SLOT_CLEARED(1)

    assertEqual(#ctx.addCounts, 1, "expected loot slot confirmation to credit LootCounter")
    assertEqual(ctx.addCounts[1].name, "Alice", "expected LootCounter credit to use the awarded player")
    assertEqual(ctx.addCounts[1].rollType, ctx.h.rollTypes.MAINSPEC, "expected LootCounter credit to use the awarded roll type")
    assertEqual(ctx.addCounts[1].count, 1, "expected LootCounter credit to use the awarded item count")
end)

test("master loot award failure error cancels pending loot counter credit", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice" },
        rollsByName = {
            Alice = 88,
        },
        model = {
            rows = {
                makeMasterRollRow("Alice", 88, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 88 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        },
    })

    assertTrue(ctx.Master._Private.BtnAward() == true, "expected master loot award request to be sent")
    assertEqual(#ctx.addCounts, 0, "expected pending award to start without LootCounter credit")

    assertTrue(type(ctx.Master.UI_ERROR_MESSAGE) == "function", "expected Master to observe UI_ERROR_MESSAGE failures")
    ctx.Master:UI_ERROR_MESSAGE("Inventory is full.")
    ctx.Master:LOOT_SLOT_CLEARED(1)

    assertEqual(#ctx.addCounts, 0, "expected failed award to avoid LootCounter credit even if a later slot event appears")
end)

test("loot service classifies master loot award failure messages", function()
    local h = newHarness()

    _G.ERR_INV_FULL = "Inventory is full."
    _G.ERR_ITEM_MAX_COUNT = "You can't carry any more of those items."
    _G.ERR_LOOT_LOCKED = "Loot is locked."
    _G.ERR_LOOT_GONE = "Loot is gone."

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    assertTrue(Loot:IsMasterLootAwardFailureMessage("Inventory is full.") == true, "expected exact inventory error to match")
    assertTrue(Loot:IsMasterLootAwardFailureMessage("Your bags are full.") == true, "expected bag-full text to match")
    assertTrue(Loot:IsMasterLootAwardFailureMessage("Player not found") == true, "expected missing player text to match")
    assertTrue(Loot:IsMasterLootAwardFailureMessage("Some unrelated message") == false, "expected unrelated text to be ignored")
    assertTrue(Loot:IsMasterLootAwardFailureMessage(nil) == false, "expected nil text to be ignored")
end)

test("loot service resolves trade awarded count from inventory stack delta", function()
    local h = newHarness()
    local link = h.registerItem(9315, "Stacked Tradeblade")
    local otherLink = h.registerItem(9316, "Other Tradeblade")
    local bagItems = {
        [0] = {
            [1] = { link = link, count = 2 },
        },
    }

    _G.GetContainerItemLink = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return item and item.link or nil
    end
    _G.GetContainerItemInfo = function(bag, slot)
        local item = bagItems[bag] and bagItems[bag][slot] or nil
        return nil, item and item.count or 0
    end

    h.feature.lootState.selectedItemCount = 3
    h.feature.lootState.tradeItemLink = link
    h.feature.itemInfo = h.feature.itemInfo or {}
    h.feature.itemInfo.tradeStartCount = 5
    h.feature.itemInfo.tradeStartBag = 0
    h.feature.itemInfo.tradeStartSlot = 1
    h.feature.itemInfo.tradeStartItemLink = link

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    assertEqual(Loot:ResolveTradeAwardedCount(), 3, "expected stack delta to drive awarded trade count")

    bagItems[0][1] = { link = otherLink, count = 2 }
    assertEqual(Loot:ResolveTradeAwardedCount(), 5, "expected replaced source slot to count the full original stack")

    h.feature.itemInfo.tradeStartCount = nil
    assertEqual(Loot:ResolveTradeAwardedCount(), 1, "expected missing trade snapshot to fall back to one item")
end)

test("loot service resolves inventory awarded count for direct keep flows", function()
    local h = newHarness()

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    h.feature.lootState.selectedItemCount = 3
    h.feature.lootState.fromInventory = false
    assertEqual(Loot:ResolveInventoryAwardedCount(), 3, "expected loot-window direct awards to use selected count")

    h.feature.lootState.fromInventory = true
    assertEqual(Loot:ResolveInventoryAwardedCount(), 1, "expected inventory multi awards to consume one copy")

    h.feature.lootState.selectedItemCount = 0
    assertEqual(Loot:ResolveInventoryAwardedCount(), 1, "expected invalid selected counts to fall back to one")
end)

test("loot service builds trade notification plans without WoW side effects", function()
    local h = newHarness()
    local link = h.registerItem(9317, "Planning Tradeblade")
    local setRaidTargetCalls = 0

    _G.SetRaidTarget = function()
        setRaidTargetCalls = setRaidTargetCalls + 1
        error("service plan must not call SetRaidTarget")
    end

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    local keepPlan = Loot:BuildTradeNotificationPlan({
        itemLink = link,
        playerName = "Tester",
        rollType = h.rollTypes.HOLD,
        isAwardRoll = false,
        selectedItemCount = 1,
        traderName = "Tester",
        options = {
            announceOnHold = true,
        },
    })

    assertEqual(keepPlan.keep, true, "expected non-award trade plan to be a keep plan")
    assertEqual(keepPlan.output, h.addon.L.ChatNoneRolledHold:format(link, "Tester"), "expected hold announce text")
    assertEqual(keepPlan.whisper, h.addon.L.WhisperHoldTrade:format(link), "expected hold whisper text")
    assertEqual(keepPlan.markerPlan, nil, "expected keep plan to avoid marker planning")

    local awardPlan = Loot:BuildTradeNotificationPlan({
        itemLink = link,
        playerName = "Alice",
        winnerName = "Alice",
        rollType = h.rollTypes.MAINSPEC,
        isAwardRoll = true,
        selectedItemCount = 1,
        traderName = "Tester",
        options = {
            announceOnWin = true,
        },
    })

    assertEqual(awardPlan.keep, false, "expected award trade plan to require external trade")
    assertEqual(awardPlan.output, h.addon.L.ChatAward:format("Alice", link), "expected award announce text")
    assertEqual(awardPlan.whisper, nil, "expected award plan to avoid keep whisper")
    assertEqual(awardPlan.markerPlan, nil, "expected single award to avoid marker planning")

    local multiPlan = Loot:BuildTradeNotificationPlan({
        itemLink = link,
        playerName = "Alice",
        winnerName = "Alice",
        rollType = h.rollTypes.MAINSPEC,
        isAwardRoll = true,
        selectedItemCount = 2,
        traderName = "Tester",
        selectedWinners = {
            { name = "Alice", roll = 98 },
            { name = "Tester", roll = 77 },
        },
        raidTargetMarkers = {
            "{rt1}",
            "{rt2}",
        },
        options = {
            announceOnWin = true,
        },
    })

    assertEqual(multiPlan.keep, false, "expected multi plan to remain an award flow")
    assertEqual(multiPlan.markerPlan.clearRaidIcons, true, "expected marker plan to request icon cleanup")
    assertEqual(multiPlan.markerPlan.raidTargets[1].name, "Tester", "expected trader marker instruction")
    assertEqual(multiPlan.markerPlan.raidTargets[1].icon, 1, "expected trader marker icon")
    assertEqual(multiPlan.markerPlan.raidTargets[2].name, "Alice", "expected winner marker instruction")
    assertEqual(multiPlan.markerPlan.raidTargets[2].icon, 2, "expected winner marker icon")
    assertTrue(type(multiPlan.output) == "string" and multiPlan.output ~= "", "expected multi-winner announce text")
    assertEqual(multiPlan.markerPlan.winnersText, "{rt1} Alice(98), {star} Tester(77)", "expected pure winners text")
    assertEqual(setRaidTargetCalls, 0, "expected service planning to avoid SetRaidTarget")
end)

test("loot service builds pure master award planning models", function()
    local h = newHarness()
    local link = h.registerItem(9318, "Award Planning Blade")

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    local targetPlan = Loot:BuildAwardTargetPlan({
        selectedItemCount = 4,
        availableItemCount = 3,
        rollsCount = 2,
    })
    assertEqual(targetPlan.target, 2, "expected award target to clamp to rolls count")
    assertEqual(targetPlan.available, 3, "expected available count to clamp independently")

    local fallbackPlan = Loot:BuildAwardTargetPlan({
        selectedItemCount = 0,
        availableItemCount = 0,
    })
    assertEqual(fallbackPlan.target, 1, "expected invalid target to fall back to one")
    assertEqual(fallbackPlan.available, 1, "expected invalid available count to fall back to one")

    local invalidSelection = Loot:ValidateInventoryTradeSelection({
        target = 2,
        selectedCount = 1,
        pickedCount = 1,
    })
    assertEqual(invalidSelection.ok, false, "expected too few picked winners to fail validation")
    assertEqual(invalidSelection.errType, "not_enough_selection", "expected exact inventory validation reason")
    assertEqual(invalidSelection.wantedCount, 2, "expected target count in validation result")
    assertEqual(invalidSelection.pickedCount, 1, "expected picked count in validation result")

    local winnersPlan = Loot:BuildMultiAwardWinnersPlan({
        target = 2,
        selectedCount = 3,
        pickedWinners = {
            { name = "Alice", roll = 98 },
            { name = "Bob", roll = "77" },
            { name = "Cara", roll = 55 },
        },
    })
    assertEqual(winnersPlan.errType, nil, "expected selected winners to produce a plan")
    assertEqual(winnersPlan.clearSelection, true, "expected service plan to request selection cleanup")
    assertEqual(#winnersPlan.winners, 2, "expected winners to clamp to requested target")
    assertEqual(winnersPlan.winners[1].name, "Alice", "expected winner order to be preserved")
    assertEqual(winnersPlan.winners[2].roll, 77, "expected winner rolls to normalize numerically")

    local emptyPlan = Loot:BuildMultiAwardWinnersPlan({
        target = 2,
        selectedCount = 0,
        pickedWinners = {},
    })
    assertEqual(emptyPlan.errType, "empty_selection", "expected empty selection reason")
    assertEqual(emptyPlan.winners, nil, "expected failed winner plan to avoid winner output")

    local statePlan = Loot:BuildMultiAwardState({
        itemLink = link,
        available = 3,
        rollType = h.rollTypes.MAINSPEC,
        winners = winnersPlan.winners,
        slotCandidates = { 1, 2 },
        slotCandidateMap = {
            [1] = true,
            [2] = true,
        },
        announceOnWin = true,
    })
    assertEqual(statePlan.state.active, true, "expected multi-award state to be active")
    assertEqual(statePlan.state.itemLink, link, "expected state to preserve item link")
    assertEqual(statePlan.state.lastCount, 3, "expected state to preserve available count")
    assertEqual(statePlan.state.currentWinner, "Alice", "expected first winner to become current")
    assertEqual(statePlan.state.pos, 2, "expected first award to remain immediate")
    assertEqual(statePlan.state.total, 2, "expected total to match planned winners")
    assertEqual(statePlan.state.announceOnWin, true, "expected state to preserve announce flag")
    assertEqual(statePlan.state.congratsSent, false, "expected new multi-award state to start unsent")
end)

test("loot service builds multi-award slot candidates from matching loot links", function()
    local h = newHarness()
    local itemLink = "|cffa335ee|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r"

    _G.GetNumLootItems = function()
        return 3
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return itemLink
        end
        if slot == 2 then
            return "|cffa335ee|Hitem:19019:1:0:0:0:0:0:0|h[Thunderfury]|h|r"
        end
        return "|cffa335ee|Hitem:18803:0:0:0:0:0:0:0|h[Finkle's Lava Dredger]|h|r"
    end

    h:load("!KRT/Services/Loot.lua")

    local Loot = h.addon.Services.Loot
    local slots, slotMap = Loot:BuildMultiAwardSlotCandidates(itemLink)
    assertEqual(#slots, 2, "expected matching multi-award loot slots")
    assertTrue(slotMap[1] == true, "expected first slot in map")
    assertTrue(slotMap[2] == true, "expected second matching item id in map")

    Loot:AddItem(itemLink, 4)
    local itemKey = h.addon.Item.GetItemStringFromLink(itemLink) or itemLink
    assertEqual(Loot:GetLootWindowItemCountByKey(itemKey), 4, "expected current item count by item key")
end)

test("master loot award timeout leaves unconfirmed loot counter credit unapplied", function()
    local ctx = setupMasterAwardHarness({
        candidates = { "Alice" },
        rollsByName = {
            Alice = 88,
        },
        model = {
            rows = {
                makeMasterRollRow("Alice", 88, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 88 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        },
    })

    assertTrue(ctx.Master._Private.BtnAward() == true, "expected master loot award request to be sent")
    assertEqual(#ctx.addCounts, 0, "expected pending award to start without LootCounter credit")
    assertTrue(ctx.h.timerCount() >= 1, "expected pending award confirmation to schedule a timeout")

    ctx.h:flushTimers()
    ctx.Master:LOOT_SLOT_CLEARED(1)

    assertEqual(#ctx.addCounts, 0, "expected timed-out award confirmation to avoid late LootCounter credit")
end)

test("group loot rolled lines queue winner type before raw won message", function()
    local h = newHarness()
    local link = h.registerItem(9180, "Protector Token")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_ROLLED_NEED and msg == "need-roll-45" then
            return 45, link, "Tester"
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertEqual(Raid:AddGroupLootMessage("need-roll-45"), "selection", "expected rolled need line to queue passive history")

    Raid:AddLoot("Tester won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected raw winner line to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected rolled need line to preserve NE type")
    assertEqual(raid.loot[1].rollValue, 45, "expected rolled need line to preserve the rolled value")
end)

test("raw group loot roll lines preserve numeric rollValue", function()
    local h = newHarness()
    local link = h.registerItem(9181, "Dawnwalkers")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function()
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("You have selected Need for: " .. link), "selection", "expected raw need selection to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("Need Roll - 67 for " .. link .. " by Tester"), "selection", "expected raw need roll line to be recognized")

    Raid:AddLoot("Tester won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected raw need roll flow to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected raw need roll flow to preserve NE type")
    assertEqual(raid.loot[1].rollValue, 67, "expected raw need roll flow to preserve numeric rollValue")
end)

test("localized group loot patterns preserve numeric rollValue without english raw fallbacks", function()
    local h = newHarness()
    local link = h.registerItem(91811, "Localized Dawnwalkers")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.LOOT_ROLL_NEED = "%s ha selezionato Necessita per: %s"
    _G.LOOT_ROLL_NEED_SELF = "Hai selezionato Necessita per: %s"
    _G.LOOT_ROLL_ROLLED_NEED = "Tiro Necessita - %d per %s da %s"
    _G.LOOT_ROLL_WON = "%s ha vinto: %s"
    _G.LOOT_ROLL_YOU_WON = "Hai vinto: %s"
    h.addon.Deformat = function()
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("Tester ha selezionato Necessita per: " .. link), "selection", "expected localized selection text to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("Tiro Necessita - 67 per " .. link .. " da Tester"), "selection", "expected localized roll text to be recognized")

    Raid:AddLoot("Tester ha vinto: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected localized group loot flow to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected localized group loot flow to preserve NE type")
    assertEqual(raid.loot[1].rollValue, 67, "expected localized group loot flow to preserve numeric rollValue")
end)

test("loot pending awards upgrade selection entries with later group roll values", function()
    local h = newHarness()
    local link = h.registerItem(9185, "Awareness Sigil")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_ROLLED_NEED and msg == "need-roll-96" then
            return 96, link, "Tester"
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("You have selected Need for: " .. link), "selection", "expected raw need selection message to queue passive history")
    assertEqual(Raid:AddGroupLootMessage("need-roll-96"), "selection", "expected rolled need line to upgrade passive history")

    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected upgraded pending award to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected upgraded pending award to keep NE type")
    assertEqual(raid.loot[1].rollValue, 96, "expected upgraded pending award to preserve the numeric rollValue")
end)

test("group loot pending awards fall back to 60 seconds without roll metadata", function()
    local h = newHarness()
    local link = h.registerItem(9187, "Delayed Needblade")
    local now = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self" then
            return 77, link
        end
        return nil
    end

    h.feature.lootState.currentRollType = h.rollTypes.FREE
    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    assertEqual(Raid:AddGroupLootMessage("need-select-self"), "selection", "expected passive group-loot selection to queue")

    now = now + 59
    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected delayed group-loot receipt to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected delayed group-loot receipt to keep the queued NE type")
end)

test("start loot roll extends passive group loot expiry beyond the fallback ttl", function()
    local h = newHarness()
    local link = h.registerItem(9188, "Tracked Needblade")
    local now = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 77 then
            return link
        end
        return nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self" then
            return 77, link
        end
        return nil
    end

    h.feature.lootState.currentRollType = h.rollTypes.FREE
    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(77, 65000)
    assertEqual(Raid:AddGroupLootMessage("need-select-self"), "selection", "expected tracked passive group-loot selection to queue")

    now = now + 70
    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected tracked passive group-loot receipt to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.NEED, "expected tracked passive group-loot receipt to keep the queued NE type")
    assertEqual(raid.loot[1].rollSessionId, "GL:1", "expected START_LOOT_ROLL tracking to stamp a passive roll session id")
end)

test("loot winner dispatch forwards passive winners immediately", function()
    local h = newHarness()
    local addLootCalls = {}
    local rollsMessages = {}
    local oldLibStub = _G.LibStub
    local mainFrame = h.makeFrame(true, "KRTMainTestFrame")

    h.addon.Diagnose = {
        D = {
            LogLootChatMsgLootRaw = "[Loot] CHAT_MSG_LOOT raw=%s",
        },
        I = {},
        W = {},
        E = {},
    }

    function mainFrame:RegisterEvent(eventName)
        self._events = self._events or {}
        self._events[eventName] = true
    end

    function mainFrame:UnregisterEvent(eventName)
        if self._events then
            self._events[eventName] = nil
        end
    end

    function mainFrame:UnregisterAllEvents()
        self._events = {}
    end

    _G.LibStub = function(name)
        if name == "LibCompat-1.0" then
            return {
                Embed = function() end,
                Print = function() end,
            }
        end
        if name == "LibBossIDs-1.0" then
            return {}
        end
        if name == "LibLogger-1.0" then
            return {
                logLevels = {
                    INFO = 1,
                    DEBUG = 2,
                },
                Embed = function(_, target)
                    target.SetLogLevel = target.SetLogLevel or function() end
                end,
            }
        end
        if name == "LibDeformat-3.0" then
            return function()
                return nil
            end
        end
        error("unexpected LibStub request: " .. tostring(name), 0)
    end

    h.addon.State.frames = { main = mainFrame }
    h:load("!KRT/Init.lua")
    h.addon.Database.SetCurrentRaid(1)
    h.addon.Services.Raid = {
        CanObservePassiveLoot = function()
            return true
        end,
    }
    local winnerOnlyCalls = 0
    local broadParserCalls = 0
    h.addon.Services.Loot = {
        ObservePassiveLootMessage = function(_, msg, winnerOnly)
            if winnerOnly then
                winnerOnlyCalls = winnerOnlyCalls + 1
            else
                broadParserCalls = broadParserCalls + 1
            end
            if (not winnerOnly) and (msg == "winner-loot" or msg == "winner-system") then
                return "winner",
                    {
                        kind = "winner",
                        msg = msg,
                        itemLink = "item-link",
                        sessionId = "GL:test",
                    }
            end
            return nil
        end,
        AddLoot = function(_, msg, rollType, rollValue, parsedLoot)
            addLootCalls[#addLootCalls + 1] = {
                msg = msg,
                rollType = rollType,
                rollValue = rollValue,
                parsedLoot = parsedLoot,
            }
        end,
    }
    h.addon.Services.Rolls = {
        CHAT_MSG_SYSTEM = function(_, msg)
            rollsMessages[#rollsMessages + 1] = msg
        end,
    }

    h.addon:CHAT_MSG_LOOT("winner-loot")
    h.addon:CHAT_MSG_SYSTEM("winner-system")
    h.addon:CHAT_MSG_SYSTEM("roll-system")

    _G.LibStub = oldLibStub

    assertEqual(#addLootCalls, 2, "expected passive winner messages on loot and system channels to reach the loot service")
    assertEqual(addLootCalls[1].msg, "winner-loot", "expected loot winner messages to materialize immediately")
    assertEqual(addLootCalls[2].msg, "winner-system", "expected system winner messages to materialize immediately")
    assertEqual(addLootCalls[1].parsedLoot.sessionId, "GL:test", "expected loot winner parsed context to reach AddLoot")
    assertEqual(addLootCalls[2].parsedLoot.sessionId, "GL:test", "expected system winner parsed context to reach AddLoot")
    assertEqual(winnerOnlyCalls, 0, "expected passive loot dispatch to use the full parser")
    assertEqual(broadParserCalls, 3, "expected loot and system channels to use the full passive parser")
    assertEqual(#rollsMessages, 2, "expected system messages to keep flowing to the rolls service")
    assertEqual(rollsMessages[1], "winner-system", "expected winner system messages to keep flowing to the rolls service")
    assertEqual(rollsMessages[2], "roll-system", "expected the rolls service to receive unrelated system messages")
end)

test("start loot roll dispatch forwards to the loot service", function()
    local h = newHarness()
    local observed = {}
    local oldLibStub = _G.LibStub
    local mainFrame = h.makeFrame(true, "KRTMainTestFrame")

    function mainFrame:RegisterEvent(eventName)
        self._events = self._events or {}
        self._events[eventName] = true
    end

    function mainFrame:UnregisterEvent(eventName)
        if self._events then
            self._events[eventName] = nil
        end
    end

    function mainFrame:UnregisterAllEvents()
        self._events = {}
    end

    _G.LibStub = function(name)
        if name == "LibCompat-1.0" then
            return {
                Embed = function() end,
                Print = function() end,
            }
        end
        if name == "LibBossIDs-1.0" then
            return {}
        end
        if name == "LibLogger-1.0" then
            return {
                logLevels = {
                    INFO = 1,
                    DEBUG = 2,
                },
                Embed = function(_, target)
                    target.SetLogLevel = target.SetLogLevel or function() end
                end,
            }
        end
        if name == "LibDeformat-3.0" then
            return function()
                return nil
            end
        end
        error("unexpected LibStub request: " .. tostring(name), 0)
    end

    h.addon.State.frames = { main = mainFrame }
    h:load("!KRT/Init.lua")
    h.addon.Database.SetCurrentRaid(1)
    h.addon.Services.Loot = {
        AddPassiveLootRoll = function(_, rollId, rollTime)
            observed.rollId = rollId
            observed.rollTime = rollTime
        end,
    }

    h.addon:START_LOOT_ROLL(44, 65000)
    _G.LibStub = oldLibStub

    assertEqual(observed.rollId, 44, "expected START_LOOT_ROLL to forward the roll id to the loot service")
    assertEqual(observed.rollTime, 65000, "expected START_LOOT_ROLL to forward the roll time to the loot service")
end)

test("chat msg addon dispatch gives loot distribution messages to the loot service first", function()
    local h = newHarness()
    local observed = {}
    local syncerCalls = 0
    local oldLibStub = _G.LibStub
    local mainFrame = h.makeFrame(true, "KRTMainTestFrame")

    function mainFrame:RegisterEvent(eventName)
        self._events = self._events or {}
        self._events[eventName] = true
    end

    function mainFrame:UnregisterEvent(eventName)
        if self._events then
            self._events[eventName] = nil
        end
    end

    function mainFrame:UnregisterAllEvents()
        self._events = {}
    end

    _G.LibStub = function(name)
        if name == "LibCompat-1.0" then
            return {
                Embed = function() end,
                Print = function() end,
            }
        end
        if name == "LibBossIDs-1.0" then
            return {}
        end
        if name == "LibLogger-1.0" then
            return {
                logLevels = {
                    INFO = 1,
                    DEBUG = 2,
                },
                Embed = function(_, target)
                    target.SetLogLevel = target.SetLogLevel or function() end
                end,
            }
        end
        if name == "LibDeformat-3.0" then
            return function()
                return nil
            end
        end
        error("unexpected LibStub request: " .. tostring(name), 0)
    end

    h.addon.State.frames = { main = mainFrame }
    h:load("!KRT/Init.lua")
    h.addon.Services.Loot = {
        HandleDistributionMessage = function(_, prefix, msg, channel, sender)
            observed.prefix = prefix
            observed.msg = msg
            observed.channel = channel
            observed.sender = sender
            return prefix == "KRTDist"
        end,
    }
    h.Database.GetSyncer = function()
        return {
            OnAddonMessage = function()
                syncerCalls = syncerCalls + 1
            end,
        }
    end

    h.addon:CHAT_MSG_ADDON("KRTDist", "ITEM|2|session-1|item:1", "RAID", "Alice")
    _G.LibStub = oldLibStub

    assertEqual(observed.prefix, "KRTDist", "expected distribution prefix to reach loot service")
    assertEqual(observed.msg, "ITEM|2|session-1|item:1", "expected distribution payload to reach loot service")
    assertEqual(observed.channel, "RAID", "expected distribution channel to reach loot service")
    assertEqual(observed.sender, "Alice", "expected distribution sender to reach loot service")
    assertEqual(syncerCalls, 0, "expected handled distribution messages to skip logger syncer fallback")
end)

test("chat msg whisper dispatch forwards to the bus", function()
    local h = newHarness()
    local observed = {}
    local oldLibStub = _G.LibStub
    local mainFrame = h.makeFrame(true, "KRTMainTestFrame")

    function mainFrame:RegisterEvent(eventName)
        self._events = self._events or {}
        self._events[eventName] = true
    end

    function mainFrame:UnregisterEvent(eventName)
        if self._events then
            self._events[eventName] = nil
        end
    end

    function mainFrame:UnregisterAllEvents()
        self._events = {}
    end

    _G.LibStub = function(name)
        if name == "LibCompat-1.0" then
            return {
                Embed = function() end,
                Print = function() end,
            }
        end
        if name == "LibBossIDs-1.0" then
            return {}
        end
        if name == "LibLogger-1.0" then
            return {
                logLevels = {
                    INFO = 1,
                    DEBUG = 2,
                },
                Embed = function(_, target)
                    target.SetLogLevel = target.SetLogLevel or function() end
                end,
            }
        end
        if name == "LibDeformat-3.0" then
            return function()
                return nil
            end
        end
        error("unexpected LibStub request: " .. tostring(name), 0)
    end

    h.addon.State.frames = { main = mainFrame }
    h:load("!KRT/Init.lua")
    h.Bus.RegisterCallback(h.addon.Events.Wow.ChatMsgWhisper, function(_, msg, sender)
        observed.msg = msg
        observed.sender = sender
    end)

    h.addon:CHAT_MSG_WHISPER("softres", "Alice")
    _G.LibStub = oldLibStub

    assertEqual(observed.msg, "softres", "expected CHAT_MSG_WHISPER to forward the whisper text to the bus")
    assertEqual(observed.sender, "Alice", "expected CHAT_MSG_WHISPER to forward the sender to the bus")
end)

test("runtime perf logger reports only slow measured blocks", function()
    local h = newHarness()
    local currentTime = 1000
    local oldLibStub = _G.LibStub
    local oldGetTime = _G.GetTime
    local mainFrame = h.makeFrame(true, "KRTMainTestFrame")

    function mainFrame:RegisterEvent(eventName)
        self._events = self._events or {}
        self._events[eventName] = true
    end

    function mainFrame:UnregisterEvent(eventName)
        if self._events then
            self._events[eventName] = nil
        end
    end

    function mainFrame:UnregisterAllEvents()
        self._events = {}
    end

    _G.GetTime = function()
        return currentTime
    end
    _G.LibStub = function(name)
        if name == "LibCompat-1.0" then
            return {
                Embed = function() end,
                Print = function() end,
            }
        end
        if name == "LibBossIDs-1.0" then
            return {}
        end
        if name == "LibLogger-1.0" then
            return {
                logLevels = {
                    INFO = 1,
                    DEBUG = 2,
                },
                Embed = function(_, target)
                    target.SetLogLevel = target.SetLogLevel or function() end
                end,
            }
        end
        if name == "LibDeformat-3.0" then
            return function()
                return nil
            end
        end
        error("unexpected LibStub request: " .. tostring(name), 0)
    end

    h.addon.State.frames = { main = mainFrame }
    h:load("!KRT/Localization/DiagnoseLog.en.lua")
    h:load("!KRT/Init.lua")

    h.addon.State.perfEnabled = true
    h.addon.State.perfThresholdMs = 5
    h.addon.hasPerf = true

    local start = h.addon:_PerfStart()
    currentTime = 1000.004
    h.addon:_PerfFinish("fast block", start, "items=1")

    assertEqual(#h.logs.info, 0, "expected fast perf blocks below threshold to stay silent")

    start = h.addon:_PerfStart()
    currentTime = 1000.012
    h.addon:_PerfFinish("slow block", start, "items=2")

    local stats = h.addon:_PerfGetStats()
    assertEqual(#stats, 2, "expected perf stats to include slow and fast measured blocks")
    assertEqual(stats[1].label, "slow block", "expected slowest perf block to sort first by total time")
    assertEqual(stats[1].count, 1, "expected slow block count to be tracked")
    assertTrue(math.abs(stats[1].totalMs - 8) < 0.0001, "expected slow block total milliseconds to be tracked")
    assertTrue(math.abs(stats[1].maxMs - 8) < 0.0001, "expected slow block max milliseconds to be tracked")
    assertTrue(math.abs(stats[1].avgMs - 8) < 0.0001, "expected slow block average milliseconds to be tracked")
    assertEqual(stats[2].label, "fast block", "expected fast measured blocks to remain visible in perf stats")
    assertEqual(stats[2].count, 1, "expected fast block count to be tracked")
    assertTrue(math.abs(stats[2].totalMs - 4) < 0.0001, "expected fast block total milliseconds to be tracked")

    h.addon:_PerfResetStats()
    assertEqual(#h.addon:_PerfGetStats(), 0, "expected perf stats reset to clear accumulated rows")

    _G.LibStub = oldLibStub
    _G.GetTime = oldGetTime

    assertContains(h.logs.info, "[Perf] slow block 8.0ms items=2", "expected slow perf block to be logged with context")
end)

test("passive loot observation is limited to group-based loot methods", function()
    local h = newHarness()
    local lootMethod = "group"
    _G.GetLootMethod = function()
        return lootMethod, nil, nil
    end
    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid

    assertTrue(Raid:CanObservePassiveLoot(), "expected Group Loot to allow passive observation")

    lootMethod = "needbeforegreed"
    assertTrue(Raid:CanObservePassiveLoot(), "expected Need Before Greed to allow passive observation")

    lootMethod = "freeforall"
    assertTrue(not Raid:CanObservePassiveLoot(), "expected Free For All to keep passive observation disabled")

    lootMethod = "roundrobin"
    assertTrue(not Raid:CanObservePassiveLoot(), "expected Round Robin to keep passive observation disabled")
end)

test("loot pending awards prefer a matching roll session over older duplicates", function()
    local h = newHarness()
    local link = h.registerItem(9189, "Session Sigil")

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:AddPendingAward(link, "Tester", h.rollTypes.MAINSPEC, 99, "RS:old")
    Loot:AddPendingAward(link, "Tester", h.rollTypes.OFFSPEC, 12, "RS:new")

    local picked = Loot:RemovePendingAward(link, "Tester", 120, "RS:new")
    local fallback = Loot:RemovePendingAward(link, "Tester", 120)

    assertTrue(picked ~= nil, "expected a pending award to match the preferred roll session")
    assertEqual(picked.rollSessionId, "RS:new", "expected pending award lookup to prefer the requested roll session")
    assertEqual(picked.rollType, h.rollTypes.OFFSPEC, "expected pending award lookup to return the matching session payload")
    assertTrue(fallback ~= nil, "expected the older pending award to remain queued after the session-specific consume")
    assertEqual(fallback.rollSessionId, "RS:old", "expected fallback consume to return the older unmatched pending award")
end)

test("master loot add loot prefers the active roll session pending award", function()
    local h = newHarness()
    local link = h.registerItem(9190, "Master Sigil")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "master", 0, 0
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Loot = h.addon.Services.Loot
    local Raid = h.addon.Services.Raid
    local itemId = h.addon.Item.GetItemIdFromLink(link)
    Loot:AddPendingAward(link, "Tester", h.rollTypes.MAINSPEC, 99, "RS:old")
    Loot:AddPendingAward(link, "Tester", h.rollTypes.OFFSPEC, 12, "RS:new")
    h.feature.lootState.rollSession = {
        id = "RS:new",
        itemKey = h.addon.Item.GetItemStringFromLink(link),
        itemId = itemId,
        itemLink = link,
        rollType = h.rollTypes.OFFSPEC,
        lootNid = 0,
        startedAt = 1000,
        endsAt = nil,
        source = "lootWindow",
        expectedWinners = 1,
        active = true,
    }

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected master loot receipt to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.OFFSPEC, "expected master loot receipt to use the pending award from the active roll session")
    assertEqual(raid.loot[1].rollValue, 12, "expected master loot receipt to keep the active roll session rollValue")
    assertEqual(raid.loot[1].rollSessionId, "RS:new", "expected master loot receipt to bind the active roll session id")
end)

test("master loot receipt does not double credit a pre-counted pending award", function()
    local h = newHarness()
    local link = h.registerItem(91901, "Counted Master Sigil")

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "master", 0, 0
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ITEM_SELF and msg == "loot-receive-self" then
            return link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Loot = h.addon.Services.Loot
    local Raid = h.addon.Services.Raid
    Loot:AddPendingAward(link, "Tester", h.rollTypes.MAINSPEC, 99, "RS:counted", nil, {
        counterApplied = true,
    })
    Raid:AddPlayerCountForRollType("Tester", h.rollTypes.MAINSPEC, 1, 1)

    Raid:AddLoot("loot-receive-self")

    local raid = h.Database.EnsureRaidById(1)
    local playerNid = Raid:GetPlayerID("Tester", 1)
    assertEqual(#raid.loot, 1, "expected master loot receipt to still create a loot entry")
    assertEqual(Raid:GetPlayerLootCountByNid(playerNid, "ms", 1), 1, "expected observed loot chat to avoid double-crediting the pre-counted award")
end)

test("loot pending awards upgrade the next FIFO duplicate entry", function()
    local h = newHarness()
    local link = h.registerItem(9186, "Twin Sigil")

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 0, nil)
    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 0, nil)
    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 96, nil)

    local first = Loot:RemovePendingAward(link, "Tester", 120)
    local second = Loot:RemovePendingAward(link, "Tester", 120)

    assertTrue(first ~= nil, "expected first pending award to exist")
    assertTrue(second ~= nil, "expected second pending award to exist")
    assertEqual(first.rollValue, 96, "expected FIFO consumption to receive the upgraded roll value first")
    assertEqual(second.rollValue, 0, "expected later duplicate pending award to remain untouched")
end)

test("loot pending award upgrades prefer an explicit matching session", function()
    local h = newHarness()
    local link = h.registerItem(91861, "Twin Sigil Sessioned")

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 0, "GL:1")
    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 0, "GL:2")
    Loot:AddPendingAward(link, "Tester", h.rollTypes.NEED, 96, "GL:2")

    local first = Loot:RemovePendingAward(link, "Tester", 120, "GL:1")
    local second = Loot:RemovePendingAward(link, "Tester", 120, "GL:2")

    assertTrue(first ~= nil, "expected first session pending award to exist")
    assertTrue(second ~= nil, "expected second session pending award to exist")
    assertEqual(first.rollValue, 0, "expected unrelated session pending award to keep its zero roll value")
    assertEqual(second.rollValue, 96, "expected explicit session upgrade to preserve the numeric roll value on the matching session")
end)

test("passive group loot selections keep duplicate item sessions separate by roll id", function()
    local h = newHarness()
    local link = h.registerItem(91862, "Duplicated Sigil")
    local now = 1000

    h.Database.GetCurrentRaid = function()
        return 1
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 77 or rollId == 78 then
            return link
        end
        return nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self-1" then
            return 77, link
        end
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self-2" then
            return 78, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Loot = h.addon.Services.Loot
    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(77, 65000)
    Raid:AddPassiveLootRoll(78, 65000)
    assertEqual(Raid:AddGroupLootMessage("need-select-self-1"), "selection", "expected first duplicate passive selection to queue")
    assertEqual(Raid:AddGroupLootMessage("need-select-self-2"), "selection", "expected second duplicate passive selection to queue")

    local first = Loot:RemovePendingAward(link, "Tester", 120, "GL:1")
    local second = Loot:RemovePendingAward(link, "Tester", 120, "GL:2")

    assertTrue(first ~= nil, "expected first passive duplicate session to remain consumable")
    assertTrue(second ~= nil, "expected second passive duplicate session to remain consumable")
    assertEqual(first.rollSessionId, "GL:1", "expected first duplicate passive selection to keep the first roll session id")
    assertEqual(second.rollSessionId, "GL:2", "expected second duplicate passive selection to keep the second roll session id")
end)

test("passive roll sessions keep native roll metadata", function()
    local h = newHarness()
    local link = h.registerItem(91865, "Native Roll Sigil", 4, "Interface\\Icons\\INV_Misc_Rune_01")
    local now = 1000

    h.Database.GetCurrentRaid = function()
        return 1
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 81 then
            return link
        end
        return nil
    end
    _G.GetLootRollItemInfo = function(rollId)
        if rollId == 81 then
            return "Interface\\Icons\\INV_Misc_Rune_01", "Native Roll Sigil", 2, 4
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    local entry = Raid:AddPassiveLootRoll(81, 65000)

    assertEqual(entry.rollId, 81, "expected passive roll session to keep native roll id")
    assertEqual(entry.sessionId, "GL:1", "expected passive roll session id to be assigned")
    assertEqual(entry.itemLink, link, "expected passive roll session to keep native item link")
    assertEqual(entry.itemName, "Native Roll Sigil", "expected passive roll session to keep native item name")
    assertEqual(entry.itemRarity, 4, "expected passive roll session to keep native item rarity")
    assertEqual(entry.itemTexture, "Interface\\Icons\\INV_Misc_Rune_01", "expected passive roll session to keep native item texture")
    assertEqual(entry.itemCount, 2, "expected passive roll session to keep native item count")
    assertTrue(type(entry.startedAt) == "number", "expected passive roll session to record start time")
    assertTrue(type(entry.expiresAt) == "number" and entry.expiresAt > entry.startedAt, "expected passive roll session to record expiry")
end)

test("passive winner context includes roll session details", function()
    local h = newHarness()
    local link = h.registerItem(91866, "Context Sigil")
    local now = 1000

    h.Database.GetCurrentRaid = function()
        return 1
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 82 then
            return link
        end
        return nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self-context" then
            return 82, 98, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Loot = h.addon.Services.Loot
    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(82, 65000)

    local observedType, parsed = Loot:GetGroupLootMessageResult("need-win-self-context")

    assertEqual(observedType, "winner", "expected winner message to be classified")
    assertEqual(parsed.kind, "winner", "expected parsed context to identify winner kind")
    assertEqual(parsed.rollId, 82, "expected parsed context to keep native roll id")
    assertEqual(parsed.sessionId, "GL:1", "expected parsed context to keep passive roll session id")
    assertEqual(parsed.itemLink, link, "expected parsed context to keep item link")
    assertEqual(parsed.itemKey, h.addon.Item.GetItemStringFromLink(link), "expected parsed context to keep item key")
    assertEqual(parsed.rollType, h.rollTypes.NEED, "expected parsed context to keep roll type")
    assertEqual(parsed.rollValue, 98, "expected parsed context to keep roll value")
    assertTrue(parsed.isPassiveWinner == true, "expected parsed context to mark passive winner")
end)

test("ambiguous duplicate passive rolls stay sessionless without roll ids", function()
    local h = newHarness()
    local link = h.registerItem(91863, "Ambiguous Sigil")
    local now = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 77 or rollId == 78 then
            return link
        end
        return nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_ROLLED_NEED and msg == "need-roll-91" then
            return 91, link, "Tester"
        end
        if pattern == _G.LOOT_ROLL_ROLLED_NEED and msg == "need-roll-87" then
            return 87, link, "Tester"
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(77, 65000)
    Raid:AddPassiveLootRoll(78, 65000)
    assertEqual(Raid:AddGroupLootMessage("Tester has selected Need for: " .. link), "selection", "expected first ambiguous selection to queue")
    assertEqual(Raid:AddGroupLootMessage("Tester has selected Need for: " .. link), "selection", "expected second ambiguous selection to queue")
    assertEqual(Raid:AddGroupLootMessage("need-roll-91"), "selection", "expected first ambiguous numeric roll to queue")
    assertEqual(Raid:AddGroupLootMessage("need-roll-87"), "selection", "expected second ambiguous numeric roll to queue")

    Raid:AddLoot("Tester won: " .. link)
    Raid:AddLoot("Tester won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 2, "expected both ambiguous duplicate passive rolls to log")
    assertEqual(raid.loot[1].rollValue, 91, "expected first ambiguous duplicate to keep the first numeric roll")
    assertEqual(raid.loot[2].rollValue, 87, "expected second ambiguous duplicate to keep the second numeric roll")
    assertEqual(raid.loot[1].rollSessionId, nil, "expected ambiguous duplicate passive rolls to stay sessionless")
    assertEqual(raid.loot[2].rollSessionId, nil, "expected ambiguous duplicate passive rolls to stay sessionless")
end)

test("passive duplicate receipts prefer resolved winner values over zero placeholders", function()
    local h = newHarness()
    local link = h.registerItem(91864, "Resolved Sigil")
    local now = 1000

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {},
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {},
            nextPlayerNid = 1,
            nextBossNid = 11,
            nextLootNid = 1,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.Database.GetLastBoss = function()
        return 10
    end
    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetTime = function()
        return now
    end
    _G.GetLootRollItemLink = function(rollId)
        if rollId == 77 or rollId == 78 then
            return link
        end
        return nil
    end
    h.addon.Deformat = function(msg, pattern)
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self-1" then
            return 77, link
        end
        if pattern == _G.LOOT_ROLL_NEED_SELF and msg == "need-select-self-2" then
            return 78, link
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self-2" then
            return 78, 97, link
        end
        if pattern == _G.LOOT_ROLL_YOU_WON_NO_SPAM_NEED and msg == "need-win-self-1" then
            return 77, 99, link
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    h.feature.Services = h.addon.Services
    h:load("!KRT/Services/Raid.lua")

    local Raid = h.addon.Services.Raid
    Raid:AddPassiveLootRoll(77, 65000)
    Raid:AddPassiveLootRoll(78, 65000)
    assertEqual(Raid:AddGroupLootMessage("need-select-self-1"), "selection", "expected first duplicate selection to queue")
    assertEqual(Raid:AddGroupLootMessage("need-select-self-2"), "selection", "expected second duplicate selection to queue")
    assertEqual(Raid:AddGroupLootMessage("need-win-self-2"), "winner", "expected second duplicate winner to resolve first")

    Raid:AddLoot("You won: " .. link)

    assertEqual(Raid:AddGroupLootMessage("need-win-self-1"), "winner", "expected first duplicate winner to resolve second")
    Raid:AddLoot("You won: " .. link)

    local raid = h.Database.EnsureRaidById(1)
    assertEqual(#raid.loot, 2, "expected both resolved duplicate passive receipts to log")
    assertEqual(raid.loot[1].rollValue, 97, "expected first receipt to consume the resolved winner value instead of a zero placeholder")
    assertEqual(raid.loot[2].rollValue, 99, "expected second receipt to keep the later resolved winner value")
end)

test("held loot lookup skips consumed duplicates and returns the next matching hold", function()
    local h = newHarness()
    local link = h.registerItem(9200, "Heldblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Tester", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {
                {
                    lootNid = 1,
                    itemId = 9200,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.HOLD,
                    bossNid = 10,
                },
                {
                    lootNid = 2,
                    itemId = 9200,
                    itemLink = link,
                    looterNid = 1,
                    rollType = h.rollTypes.HOLD,
                    bossNid = 10,
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 3,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local raid = h.Database.EnsureRaidById(1)

    assertEqual(Raid:GetHeldLootNid(link, 1, "Tester", 0), 2, "expected newest matching hold row to be selected first")

    raid.loot[2].rollType = h.rollTypes.MAINSPEC

    assertEqual(Raid:GetHeldLootNid(link, 1, "Tester", 0), 1, "expected lookup to fall back to the remaining hold row after consumption")
end)

test("loot tracking snapshot exposes runtime and authoritative loot state", function()
    local h = newHarness()
    local windowLink = h.registerItem(9201, "Windowblade")
    local historyLink = h.registerItem(9202, "Historyblade")
    local historyItemString = h.addon.Item.GetItemStringFromLink(historyLink)
    local windowItemString = h.addon.Item.GetItemStringFromLink(windowLink)

    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", countMS = 0 },
            },
            bossKills = {
                { bossNid = 10, boss = "Sapphiron" },
            },
            loot = {
                {
                    lootNid = 7,
                    itemId = 9202,
                    itemName = "Historyblade",
                    itemString = historyItemString,
                    itemLink = historyLink,
                    itemRarity = 4,
                    itemTexture = "icon-9202",
                    itemCount = 2,
                    looterNid = 1,
                    rollType = h.rollTypes.MAINSPEC,
                    rollValue = 88,
                    rollSessionId = "RS:logged",
                    bossNid = 10,
                    time = 1234,
                    source = "CHAT_MSG_LOOT",
                },
            },
            nextPlayerNid = 2,
            nextBossNid = 11,
            nextLootNid = 8,
        },
    })
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h.addon.Services.Raid = {
        GetPlayerName = function(_, playerNid)
            if tonumber(playerNid) == 1 then
                return "Alice"
            end
            return nil
        end,
    }

    _G.GetLootMethod = function()
        return "group", nil, nil
    end
    _G.GetItemFamily = function()
        return 0
    end
    _G.GetNumLootItems = function()
        return 1
    end
    _G.LootSlotIsItem = function(slot)
        return slot == 1
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return windowLink
        end
        return nil
    end
    _G.GetLootSlotInfo = function(slot)
        if slot == 1 then
            return "icon-9201", "Windowblade", 1, 4, false, false, nil, true
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:FetchLoot()
    Loot:AddPendingAward(windowLink, "Alice", h.rollTypes.NEED, 91, "GL:1", 2000)

    h.feature.lootState.rollSession = {
        id = "RS:1",
        itemKey = windowItemString,
        itemId = 9201,
        itemLink = windowLink,
        rollType = h.rollTypes.MAINSPEC,
        lootNid = 0,
        bossNid = 10,
        startedAt = 1000,
        endsAt = nil,
        source = "lootWindow",
        expectedWinners = 1,
        active = true,
    }
    h.feature.raidState.passiveLootRolls = {
        byItemKey = {},
        bySessionId = {
            ["GL:1"] = {
                rollId = 44,
                itemLink = windowLink,
                itemKey = windowItemString,
                sessionId = "GL:1",
                expiresAt = 1300,
                bossNid = 10,
            },
        },
        byRollId = {},
        nextSessionId = 2,
    }
    h.feature.raidState.loggedPassiveLoot = {
        [windowItemString .. "\001Alice"] = {
            {
                rollSessionId = "GL:1",
                expiresAt = 1400,
            },
        },
    }

    local snapshot = Loot:GetTrackingSnapshot()

    assertEqual(snapshot.schemaVersion, 1, "expected a stable tracking snapshot schema version")
    assertEqual(snapshot.state.currentRaid, 1, "expected snapshot to target the current raid")
    assertEqual(snapshot.window.items[1].itemLink, windowLink, "expected snapshot to include the current loot window item")
    assertTrue(snapshot.window.items[1].selected == true, "expected current loot window item to be marked as selected")
    assertEqual(snapshot.rolls.session.id, "RS:1", "expected snapshot to include the active roll session")
    assertEqual(snapshot.rolls.pendingAwards[1].rollSessionId, "GL:1", "expected pending award snapshot to preserve roll session ids")
    assertEqual(snapshot.rolls.passive.entries[1].sessionId, "GL:1", "expected passive loot snapshot to expose the passive roll session")
    assertEqual(snapshot.rolls.loggedReceipts[1].looter, "Alice", "expected logged passive loot snapshot to expose the looter name")
    assertEqual(snapshot.history.loot[1].looterName, "Alice", "expected history snapshot to resolve looter names")
    assertEqual(snapshot.history.loot[1].bossName, "Sapphiron", "expected history snapshot to resolve boss names")
end)

test("loot window fetch defers item cache warming", function()
    local h = newHarness()
    local itemLink = h.registerItem(9202, "Deferred Cache Blade")
    local warmed = {}

    h.addon.Item.WarmItemCache = function(link)
        warmed[#warmed + 1] = link
    end

    _G.GetItemFamily = function()
        return 0
    end
    _G.GetNumLootItems = function()
        return 1
    end
    _G.LootSlotIsItem = function(slot)
        return slot == 1
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return itemLink
        end
        return nil
    end
    _G.GetLootSlotInfo = function(slot)
        if slot == 1 then
            return "icon-9202", "Deferred Cache Blade", 1, 4, false, false, nil, true
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")

    h.addon.Services.Loot:FetchLoot()

    assertEqual(#warmed, 0, "expected loot fetch to avoid synchronous item cache warming")
    assertEqual(h.timerCount(), 1, "expected deferred item cache warming to schedule one timer")

    h:flushTimers()

    assertEqual(#warmed, 1, "expected deferred item cache warming to run after the timer")
    assertEqual(warmed[1], itemLink, "expected deferred item cache warming to preserve the item link")
    assertEqual(h.timerCount(), 0, "expected item cache warm queue to drain")
end)

test("loot window fetch defers expensive auto loot suggestion metadata", function()
    local h = newHarness()
    local itemLink = h.registerItem(9204, "Deferred BoE Blade")
    local getItemInfoCalls = 0
    local tooltipCalls = 0

    h.addon.Item.WarmItemCache = function() end
    h.addon.Item.GetItemBindFromTooltip = function(link)
        tooltipCalls = tooltipCalls + 1
        if link == itemLink then
            return 2
        end
        return nil
    end

    _G.GetItemInfo = function(value)
        getItemInfoCalls = getItemInfoCalls + 1
        if value == itemLink then
            return "Deferred BoE Blade", itemLink, 4, nil, nil, nil, nil, nil, nil, "Icon9204"
        end
        return nil
    end
    _G.GetItemFamily = function()
        return 0
    end
    _G.GetNumLootItems = function()
        return 1
    end
    _G.LootSlotIsItem = function(slot)
        return slot == 1
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return itemLink
        end
        return nil
    end
    _G.GetLootSlotInfo = function(slot)
        if slot == 1 then
            return "Icon9204", "Deferred BoE Blade", 1, 4, false, false, nil, true
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:FetchLoot()

    assertEqual(getItemInfoCalls, 0, "expected loot fetch to avoid synchronous GetItemInfo for auto loot suggestions")
    assertEqual(tooltipCalls, 0, "expected loot fetch to avoid synchronous tooltip scans for auto loot suggestions")
    assertEqual(Loot:GetAutoLootSuggestion(1).action, "none", "expected expensive BoE suggestion to stay pending during loot fetch")
    assertEqual(h.timerCount(), 1, "expected deferred metadata work to reuse the item cache warm timer")

    h:flushTimers()

    assertEqual(tooltipCalls, 1, "expected deferred metadata work to scan the tooltip after the loot-open path")
    assertEqual(Loot:GetAutoLootSuggestion(1).action, "bank", "expected deferred metadata work to resolve the BoE bank suggestion")
end)

test("loot tracking snapshot includes master loot candidates by slot", function()
    local h = newHarness()
    local itemLink = h.registerItem(9203, "Masterblade")

    h.addon.GetNumGroupMembers = function()
        return 2
    end
    _G.GetLootMethod = function()
        return "master", 3, 0
    end
    _G.GetMasterLootCandidate = function(slotOrIndex, index)
        local candidates = { "Alice", "Bob" }
        if index == nil then
            return candidates[slotOrIndex]
        end
        if slotOrIndex == 1 then
            return candidates[index]
        end
        return nil
    end
    _G.GetItemFamily = function()
        return 0
    end
    _G.GetNumLootItems = function()
        return 1
    end
    _G.LootSlotIsItem = function(slot)
        return slot == 1
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return itemLink
        end
        return nil
    end
    _G.GetLootSlotInfo = function(slot)
        if slot == 1 then
            return "icon-9203", "Masterblade", 1, 4, false, false, nil, true
        end
        return nil
    end

    h:load("!KRT/Services/Loot.lua")
    local Loot = h.addon.Services.Loot

    Loot:FetchLoot()
    local snapshot = Loot:GetTrackingSnapshot()

    assertEqual(snapshot.masterLoot.method, "master", "expected snapshot to expose the active master loot method")
    assertEqual(snapshot.masterLoot.masterLooterPartyId, 3, "expected snapshot to preserve master looter metadata")
    assertEqual(#snapshot.masterLoot.slots, 1, "expected snapshot to expose one master loot slot")
    assertEqual(snapshot.masterLoot.slots[1].slot, 1, "expected snapshot to resolve the underlying loot slot index")
    assertEqual(snapshot.masterLoot.slots[1].candidates[2].name, "Bob", "expected snapshot to expose per-slot master loot candidates")
end)

test("single winner ctrl-click clears and replaces the prefilled multiselect winner", function()
    local h = newHarness()
    local link = h.registerItem(9300, "Winnerblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:SetRollRecordingEnabled(false)
    Rolls:GetDisplayModel()

    assertEqual(h.addon.UI.Selection.GetCount("MLRollWinners"), 0, "expected Rolls service to stop owning prefilled single-award multiselect state")
    assertEqual(h.feature.lootState.winner, nil, "expected Rolls service to stop mutating the selected winner mirror directly")
end)

test("roll strategies preserve reserved plus ordering at cutoff", function()
    local h = newHarness()
    h:load("!KRT/Services/Rolls/Strategies.lua")
    h:load("!KRT/Services/Rolls/Resolution.lua")

    local state = {
        responsesByPlayer = {
            Alice = { status = "ROLL", bestRoll = 90, bucket = "SR", isEligible = true },
            Bob = { status = "ROLL", bestRoll = 90, bucket = "SR", isEligible = true },
            Cara = { status = "ROLL", bestRoll = 95, bucket = "FREE", isEligible = true },
        },
    }
    local ctx = {
        state = state,
        rollTypes = h.rollTypes,
        isSelectableRollResponse = function(response)
            return response.status == "ROLL" and response.isEligible == true
        end,
        getPlusForItem = function(_, name)
            return name == "Alice" and 4 or 1
        end,
        isPlusSystemEnabled = function()
            return true
        end,
        isSortAscending = function()
            return false
        end,
        getExpectedWinnerCount = function()
            return 1
        end,
    }

    local resolved = h.addon.Services.Rolls._Resolution.BuildResolvedEntries(ctx, 1201, h.rollTypes.RESERVED)
    assertEqual(resolved[1].name, "Alice", "expected reserved plus to beat equal roll")
    assertEqual(resolved[2].name, "Bob", "expected lower plus to sort second")
    assertEqual(resolved[3].name, "Cara", "expected non-SR fallback after SR bucket")
end)

test("roll strategies keep multi-copy partial winners before cutoff tie", function()
    local h = newHarness()
    h:load("!KRT/Services/Rolls/Strategies.lua")
    h:load("!KRT/Services/Rolls/Resolution.lua")

    local entries = {
        { name = "Alice", bucket = "FREE", bucketPriority = 1, roll = 99 },
        { name = "Bob", bucket = "FREE", bucketPriority = 1, roll = 88 },
        { name = "Cara", bucket = "FREE", bucketPriority = 1, roll = 88 },
    }
    local ctx = {
        getExpectedWinnerCount = function()
            return 2
        end,
    }

    local resolution = h.addon.Services.Rolls._Resolution.BuildResolution(ctx, entries, false)
    assertEqual(#resolution.autoWinners, 1, "expected one automatic winner before cutoff tie")
    assertEqual(resolution.autoWinners[1].name, "Alice", "expected top roll to stay auto winner")
    assertEqual(#resolution.tiedNames, 2, "expected cutoff tie candidates")
    assertTrue(resolution.requiresManualResolution == true, "expected manual resolution for cutoff tie")
end)

test("accepted roll stays eligible after using the last allowed roll", function()
    local h = newHarness()
    local link = h.registerItem(9304, "Eligibilityblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:SetRollRecordingEnabled(false)

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    local model = Rolls:GetDisplayModel()
    local first = model and model.rows and model.rows[1]

    assertTrue(eligibility ~= nil and eligibility.ok == true, "expected accepted winner to remain candidate-eligible after consuming the quota")
    assertTrue(eligibility.canSubmit ~= true, "expected accepted winner to be blocked from submitting another roll")
    assertTrue(model ~= nil and model.resolution and model.resolution.autoWinners[1] ~= nil, "expected the accepted winner to remain in the resolver output")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the accepted winner to remain auto-selected after countdown finalization")
    assertTrue(first ~= nil, "expected an eligible winner row in the display model")
    assertEqual(first.status, "ROLL", "expected recorded response to stay in ROLL status")
    assertTrue(first.isEligible == true, "expected recorded response to stay eligible in the UI model")
end)

test("resolved winner uses rollWinner from the raw display model", function()
    local h = newHarness()
    local link = h.registerItem(9305, "Resolvedwinnerblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()

    assertEqual(model.rollWinner, "Alice", "expected the raw display model to expose the roll winner")
    assertEqual(Rolls:GetResolvedWinner(model), "Alice", "expected resolved winner to read rollWinner")
end)

test("roll display model reuses row tables and clears ui decoration fields", function()
    local h = newHarness()
    local link = h.registerItem(9306, "Rowreuseblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function(_, playerName)
            return playerName == "Bob" and "ROGUE" or "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:SetRollRecordingEnabled(false)

    local firstModel = Rolls:GetDisplayModel()
    local firstRows = firstModel.rows
    local firstAlice = firstRows[1]
    local firstBob = firstRows[2]
    firstAlice.displayName = "> Alice <"
    firstAlice.isSelected = true
    firstAlice.isFocused = true
    firstAlice.canClick = true
    firstAlice.showStar = true

    local secondModel = Rolls:GetDisplayModel()

    assertTrue(secondModel == firstModel, "expected roll display model table to be reused")
    assertTrue(secondModel.rows == firstRows, "expected roll rows list table to be reused")
    assertTrue(secondModel.rows[1] == firstAlice, "expected Alice row table to be reused")
    assertTrue(secondModel.rows[2] == firstBob, "expected Bob row table to be reused")
    assertEqual(secondModel.rows[1].name, "Alice", "expected reused row to refresh Alice data")
    assertEqual(secondModel.rows[2].class, "ROGUE", "expected reused row to refresh class data")
    assertTrue(secondModel.rows[1].displayName == nil, "expected pure rolls model to clear UI display-name decoration")
    assertTrue(secondModel.rows[1].isSelected == nil, "expected pure rolls model to clear UI selection decoration")
    assertTrue(secondModel.rows[1].isFocused == nil, "expected pure rolls model to clear UI focus decoration")
    assertTrue(secondModel.rows[1].canClick == nil, "expected pure rolls model to clear UI click decoration")
    assertTrue(secondModel.rows[1].showStar == nil, "expected pure rolls model to clear UI star decoration")
end)

test("reserved rolls exclude non-reservers and expose softres context in the display model", function()
    local h = newHarness()
    local link = h.registerItem(9305, "Reservedcontextblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
        GetCurrentItemCount = function()
            return 2
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            if playerName == "Alice" or playerName == "Cara" then
                return "raid1"
            end
            return "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function(itemId, name)
            if itemId == 9305 and (name == "Alice" or name == "Bob") then
                return 1
            end
            return 0
        end,
        GetPlayersForItem = function(itemId)
            if itemId == 9305 then
                return { "Alice", "Bob" }
            end
            return {}
        end,
        GetItemReserveContext = function(itemId)
            if itemId == 9305 then
                return {
                    itemId = 9305,
                    hasReserves = true,
                    hasPresentReserve = true,
                    totalReserveCount = 2,
                    presentReserveCount = 1,
                    missingReserveCount = 1,
                    presentPlayers = { "Alice" },
                    missingPlayers = { "Bob" },
                    presentPlayersText = "Alice",
                    missingPlayersText = "Bob",
                    rosterFilterApplied = true,
                }
            end
            return nil
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.RESERVED
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SubmitDebugRoll("Cara", 99) ~= true, "expected a non-reserver to be denied during SR roll intake")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 88) == true, "expected an in-raid reserver to be accepted during SR roll intake")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice
    local bob
    local cara

    for i = 1, #(model.rows or {}) do
        local row = model.rows[i]
        if row.name == "Alice" then
            alice = row
        elseif row.name == "Bob" then
            bob = row
        elseif row.name == "Cara" then
            cara = row
        end
    end

    assertTrue(model ~= nil and model.srContext ~= nil, "expected SR display model to expose softres context")
    assertEqual(model.srContext.totalReserveCount, 2, "expected SR model context to count all reservers")
    assertEqual(model.srContext.eligibleReserveCount, 1, "expected SR model context to count in-raid reservers")
    assertEqual(model.srContext.missingReserveCount, 1, "expected SR model context to count reservers outside raid")
    assertEqual(model.srContext.eligibleReserveNames[1], "Alice", "expected SR model context to list eligible reservers")
    assertEqual(model.srContext.missingReserveNames[1], "Bob", "expected SR model context to list missing reservers")
    assertEqual(model.srSummaryText, "SR 1 present / 1 missing", "expected SR model to expose compact present/missing text")
    assertEqual(model.lootCopyText, "Copies: 2", "expected roll display model to expose loot-window copy count")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected resolver to pick only the eligible SR roller")
    assertTrue(alice ~= nil and alice.isReserved == true and alice.isEligible == true, "expected Alice to remain an eligible SR row")
    assertTrue(bob ~= nil and bob.isReserved == true and bob.isEligible ~= true, "expected out-of-raid reserver to stay visible but ineligible")
    assertEqual(bob.reason, "not_in_raid", "expected out-of-raid reserver to carry not-in-raid reason")
    assertTrue(cara == nil, "expected non-reserver roll attempts to stay out of the SR display model")
end)

test("late accepted rolls show OOT info when intake remains open", function()
    local h = newHarness()
    local link = h.registerItem(9306, "Outoftimeblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:StartCountdown(5) == true, "expected countdown to start")
    h:flushTimers()

    local ok, reason = Rolls:SubmitDebugRoll("Alice", 87)
    local model = Rolls:GetDisplayModel()
    local row = model and model.rows and model.rows[1]

    assertTrue(ok == true, "expected late roll to stay accepted while intake is open")
    assertEqual(reason, nil, "expected no rejection reason for accepted late roll")
    assertEqual(#Rolls:GetRolls(), 1, "expected the accepted late roll to be recorded")
    assertTrue(model ~= nil and model.resolution ~= nil, "expected a display model with resolution")
    assertEqual(#(model.resolution.autoWinners or {}), 0, "expected OOT late roll to stay out of resolver winners")
    assertTrue(row ~= nil, "expected the late roll to appear in the display model")
    assertEqual(row.status, "ROLL", "expected accepted late roll to keep ROLL status")
    assertTrue(row.isEligible == true, "expected accepted late roll to stay eligible")
    assertTrue(row.selectionAllowed ~= true, "expected accepted OOT row to remain non-selectable")
    assertEqual(row.infoText, "OOT", "expected accepted late roll to be tagged as OOT in info")
    assertTrue(Rolls:ShouldUseTieReroll(model) ~= true, "expected OOT late roll to never trigger tie reroll")
end)

test("late tied OOT rolls stay excluded from manual resolution and reroll", function()
    local h = newHarness()
    local link = h.registerItem(9307, "Outoftimetieblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:StartCountdown(5) == true, "expected countdown to start")
    h:flushTimers()

    local okAlice, reasonAlice = Rolls:SubmitDebugRoll("Alice", 96)
    local okBob, reasonBob = Rolls:SubmitDebugRoll("Bob", 96)
    local model = Rolls:GetDisplayModel()
    local rows = model and model.rows or {}
    local aliceRow
    local bobRow

    for i = 1, #rows do
        local row = rows[i]
        if row and row.name == "Alice" then
            aliceRow = row
        elseif row and row.name == "Bob" then
            bobRow = row
        end
    end

    assertTrue(okAlice == true and okBob == true, "expected tied late rolls to be accepted while intake stays open")
    assertEqual(reasonAlice, nil, "expected no rejection reason for Alice")
    assertEqual(reasonBob, nil, "expected no rejection reason for Bob")
    assertTrue(model ~= nil and model.resolution ~= nil, "expected a display model with resolution")
    assertTrue(model.resolution.requiresManualResolution ~= true, "expected OOT-only ties to stay out of manual resolution")
    assertEqual(#(model.resolution.autoWinners or {}), 0, "expected OOT-only ties to produce no resolver winners")
    assertTrue(Rolls:ShouldUseTieReroll(model) ~= true, "expected OOT-only ties to never trigger tie reroll")
    assertTrue(aliceRow ~= nil and bobRow ~= nil, "expected tied rows to appear in the display model")
    assertTrue(aliceRow.selectionAllowed ~= true and bobRow.selectionAllowed ~= true, "expected tied OOT rows to remain non-clickable/non-selectable")
    assertEqual(aliceRow.infoText, "OOT", "expected Alice late tie row to retain OOT tag")
    assertEqual(bobRow.infoText, "OOT", "expected Bob late tie row to retain OOT tag")
end)

test("harness raid capability service mirrors shared loot and leadership policy", function()
    local h = newHarness()
    local raid = h.addon.Services.Raid

    h:setRaidRoleState({
        inRaid = true,
        rank = 0,
        isMasterLooter = false,
    })

    local lootState = raid:GetCapabilityState("loot")
    local inventoryTradeState = raid:GetCapabilityState("inventory_trade")
    local counterState = raid:GetCapabilityState("loot_counter_broadcast")

    assertEqual(lootState.allowed, false, "expected loot capability to require master looter in raid")
    assertEqual(lootState.reason, "missing_master_looter", "expected missing ML denial reason")
    assertEqual(inventoryTradeState.allowed, false, "expected inventory trade capability to require loot or leadership in raid")
    assertEqual(inventoryTradeState.reason, "missing_loot_or_leadership", "expected inventory trade denial reason")
    assertEqual(counterState.allowed, false, "expected counter broadcast to require raid leadership")
    assertEqual(counterState.reason, "missing_leadership", "expected leadership denial reason")
    assertTrue(raid:EnsureMasterOnlyAccess() ~= true, "expected shared master-only guard to block when loot access is denied")
    assertContains(h.logs.warn, "L.WarnMLOnlyMode", "expected guard denial to use the shared warning")

    h:setRaidRoleState({
        inRaid = true,
        rank = 1,
        isMasterLooter = false,
    })

    assertTrue(raid:CanUseCapability("loot") ~= true, "expected assistant without ML to stay outside loot capability")
    assertTrue(raid:CanUseCapability("inventory_trade") == true, "expected assistant to use inventory trade capability")

    h:setRaidRoleState({
        inRaid = true,
        rank = 1,
        isMasterLooter = true,
    })

    assertTrue(raid:CanUseCapability("loot") == true, "expected ML ownership to re-enable loot capability")
    assertTrue(raid:CanUseCapability("inventory_trade") == true, "expected ML ownership to enable inventory trade capability")
    assertTrue(raid:CanUseCapability("loot_counter_broadcast") == true, "expected raid leadership to re-enable counter broadcast")
    assertTrue(raid:CanUseCapability("ready_check") == true, "expected leadership to re-enable ready checks")
end)

test("english localization defines the shared Clear button label", function()
    local h = newHarness()

    h:load("!KRT/Localization/localization.en.lua")

    assertEqual(h.addon.L.BtnClear, "Clear", "expected shared Clear button label to be localized")
end)

test("master roll intake reopens after announcing rolls with service-owned session bootstrap", function()
    local h = newHarness()
    local link = h.registerItem(9321, "Countdownblade")

    setHarnessOption(h, "Rolls", "countdownDuration", 5, { countdownDuration = 5 })
    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link, count = 1 }
        end,
        GetItemLink = function(index)
            if index ~= 1 then
                return nil
            end
            return link
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local Private = Master._Private
    local frame = h.makeFrame(true, "KRTMaster")
    _G.KRTMasterItemCount = h.makeFrame(true, "KRTMasterItemCount")
    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.fromInventory = false

    Private.BtnMS()

    assertEqual(h.feature.lootState.rollStarted, true, "expected MS announce to reopen the roll-started state")
    assertEqual(h.timerCount(), 0, "expected no countdown timer before clicking the countdown button")

    Private.BtnCountdown(nil, "LeftButton")

    assertEqual(h.timerCount(), 2, "expected countdown click to schedule ticker and end timer")
end)

test("master assignment buttons stay disabled until a target is selected", function()
    local h = newHarness()
    local perfRows = {}

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.addon.hasPerf = true
    h.addon._PerfStart = function()
        return #perfRows + 1
    end
    h.addon._PerfFinish = function(_, label, startedAt, details)
        perfRows[#perfRows + 1] = {
            label = label,
            startedAt = startedAt,
            details = details,
        }
    end
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.fromInventory = false
    h.feature.lootState.holder = nil
    h.feature.lootState.banker = nil
    h.feature.lootState.disenchanter = nil

    refreshMasterFrameForTest(Master)

    assertEqual(#perfRows, 1, "expected first Master refresh to record one perf row")
    assertEqual(perfRows[1].label, "Master.RefreshUI", "expected Master refresh perf label")
    assertEqual(perfRows[1].startedAt, 1, "expected Master refresh to finish the started measurement")
    assertContains({ perfRows[1].details }, "items=1 rolls=0", "expected Master refresh perf context")
    assertEqual(_G.KRTMasterHoldBtn._enabled, false, "expected Hold to disable when no holder is selected")
    assertEqual(_G.KRTMasterBankBtn._enabled, false, "expected Bank to disable when no banker is selected")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, false, "expected Disenchant to disable when no disenchanter is selected")

    h.feature.lootState.holder = "Alice"
    h.feature.lootState.banker = "Bob"
    h.feature.lootState.disenchanter = nil

    refreshMasterFrameForTest(Master)

    assertEqual(#perfRows, 2, "expected second Master refresh to record one perf row")
    assertEqual(perfRows[2].label, "Master.RefreshUI", "expected repeated Master refresh perf label")
    assertEqual(_G.KRTMasterHoldBtn._enabled, true, "expected Hold to enable when a holder is selected")
    assertEqual(_G.KRTMasterBankBtn._enabled, true, "expected Bank to enable when a banker is selected")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, false, "expected Disenchant to stay disabled without a target")
end)

test("master enables inventory Trade in group loot without unlocking loot-window actions", function()
    local h = newHarness()
    local link = h.registerItem(9410, "Group Trade Blade")

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link, count = 1 }
        end,
        GetItemLink = function()
            return link
        end,
        ItemExists = function()
            return true
        end,
    }
    h.addon.Services.Raid = {
        CanUseCapability = function(_, capability)
            return capability == "inventory_trade" or capability == "ready_check"
        end,
        EnsureMasterOnlyAccess = function()
            return false
        end,
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    installMasterFrameParts(h, frame)
    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true
    h.feature.lootState.holder = "Alice"
    h.feature.lootState.banker = "Bob"
    h.feature.lootState.disenchanter = "Cara"

    h.addon.Services.Rolls.GetDisplayModel = function()
        return {
            rows = {
                { name = "Alice", status = "ROLL", roll = 98, selectionAllowed = true, isEligible = true },
            },
            winner = "Alice",
            selectionAllowed = true,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 98 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        }
    end
    h.addon.Services.Rolls.GetHighestRoll = function()
        return 98
    end
    h.addon.Services.Rolls.GetRollStatus = function()
        return h.rollTypes.MAINSPEC, false, false, false
    end

    refreshMasterFrameForTest(Master)

    assertEqual(_G.KRTMasterAwardBtn:GetText(), "Trade", "expected inventory action to render as Trade")
    assertEqual(_G.KRTMasterAwardBtn._enabled, true, "expected inventory Trade to enable through inventory_trade access")
    assertEqual(_G.KRTMasterHoldBtn._enabled, true, "expected inventory Hold trade to enable through inventory_trade access")
    assertEqual(_G.KRTMasterBankBtn._enabled, true, "expected inventory Bank trade to enable through inventory_trade access")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, true, "expected inventory DE trade to enable through inventory_trade access")
    assertEqual(_G.KRTMasterMSBtn._enabled, true, "expected inventory rolls to enable through inventory_trade access")

    h.feature.lootState.fromInventory = false
    refreshMasterFrameForTest(Master)

    assertEqual(_G.KRTMasterAwardBtn:GetText(), "Award", "expected loot-window action to render as Award")
    assertEqual(_G.KRTMasterAwardBtn._enabled, false, "expected loot-window Award to stay gated behind Master Loot access")
    assertEqual(_G.KRTMasterHoldBtn._enabled, false, "expected loot-window Hold to stay gated behind Master Loot access")
    assertEqual(_G.KRTMasterBankBtn._enabled, false, "expected loot-window Bank to stay gated behind Master Loot access")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, false, "expected loot-window DE to stay gated behind Master Loot access")
    assertEqual(_G.KRTMasterMSBtn._enabled, false, "expected loot-window roll starts to stay gated behind Master Loot access")
end)

test("master auto loot suggestions stay visual only", function()
    local h = newHarness()
    local link = h.registerItem(9400, "Suggestion Dust")

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link, count = 1 }
        end,
        GetItemLink = function()
            return link
        end,
        GetAutoLootSuggestion = function()
            return {
                action = "disenchant",
                automatic = false,
                reason = "enchanting_material",
                rollType = h.rollTypes.DISENCHANT,
                targetKey = "disenchanter",
            }
        end,
        ItemExists = function()
            return true
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "Status",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.fromInventory = false
    h.feature.lootState.holder = "Holder"
    h.feature.lootState.banker = "Banker"
    h.feature.lootState.disenchanter = "Shardmaster"

    refreshMasterFrameForTest(Master)

    assertEqual(_G.KRTMasterStatus:GetText(), "Ready. Suggestion: DE.", "expected status to show the suggested action")
    assertEqual(_G.KRTMasterHoldBtn._glow, false, "expected Hold to stay unhighlighted")
    assertEqual(_G.KRTMasterBankBtn._glow, false, "expected Bank to stay unhighlighted")
    assertEqual(_G.KRTMasterDisenchantBtn._glow, true, "expected Disenchant suggestion to highlight DE only")
end)

test("master workflow model names rolling and ready states without changing status text", function()
    local h = newHarness()

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local FlowState = h.addon.Services.Master.FlowState

    local idle = FlowState.BuildState({
        currentFlowState = "idle",
        hasItem = false,
        rollModel = {},
    })
    local ready = FlowState.BuildState({
        currentFlowState = "loot",
        hasItem = true,
        rollModel = {},
    })
    local srReady = FlowState.BuildState({
        currentFlowState = "loot",
        hasItem = true,
        rollModel = {},
        reserveContext = {
            hasReserves = true,
            totalReserveCount = 2,
            presentReserveCount = 1,
        },
    })
    local srRolling = FlowState.BuildState({
        currentFlowState = "rolling",
        hasItem = true,
        rollModel = {
            isSR = true,
            selectionAllowed = false,
            srContext = {
                hasReserves = true,
                eligibleReserveCount = 1,
                totalReserveCount = 2,
            },
        },
    })
    local tie = FlowState.BuildState({
        currentFlowState = "rolling",
        hasItem = true,
        rollModel = {
            selectionAllowed = true,
            requiredWinnerCount = 1,
            msCount = 0,
            resolution = {
                requiresManualResolution = true,
            },
        },
    })

    assertEqual(idle.name, "idle", "expected no-item state to be named idle")
    assertEqual(idle.statusText, "Select or drag an item to start.", "expected idle status text to stay unchanged")
    assertEqual(ready.name, "ready", "expected normal loot state to be named ready")
    assertEqual(ready.statusText, "Ready. Start a roll or use Hold, Bank, or DE.", "expected ready status text to stay unchanged")
    assertEqual(srReady.name, "ready", "expected SoftRes context to keep the ready workflow name")
    assertEqual(srReady.statusText, "Ready. SR 1 present / 1 missing.", "expected ready state to summarize present and missing SoftRes players")
    assertEqual(srRolling.name, "rolling", "expected SR rolling context to keep the normal rolling workflow name")
    assertEqual(srRolling.statusText, "Rolls are open. SR 1 present / 1 missing. Responses: 0.", "expected SR rolling state to keep SoftRes context visible")
    assertEqual(tie.name, "resolve_tie", "expected manual tie state to be named explicitly")
    assertEqual(tie.statusText, "Tie at the cutoff. Select winners manually before awarding.", "expected tie status text to stay unchanged")
end)

test("master workflow model centralizes button capabilities without changing gating", function()
    local h = newHarness()

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local FlowState = h.addon.Services.Master.FlowState

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = 0
    h.feature.lootState.fromInventory = false

    local ready = FlowState.BuildState({
        canAwardSelection = false,
        canRoll = false,
        countdownRunning = false,
        currentFlowState = "loot",
        hasEligibleRaidReserve = true,
        hasItem = true,
        hasLootAccess = true,
        hasReadyCheckAccess = true,
        record = false,
        rollModel = {},
        rolled = false,
    })
    local countdown = FlowState.BuildState({
        canAwardSelection = false,
        canRoll = true,
        countdownRunning = true,
        currentFlowState = "countdown",
        hasEligibleRaidReserve = true,
        hasItem = true,
        hasLootAccess = true,
        hasReadyCheckAccess = true,
        record = true,
        rollModel = {},
        rolled = false,
    })
    h.feature.lootState.rollsCount = 1
    local awardReady = FlowState.BuildState({
        canAwardSelection = true,
        canRoll = false,
        countdownRunning = false,
        currentFlowState = "rolling",
        displayedWinner = "Alice",
        hasEligibleRaidReserve = true,
        hasItem = true,
        hasLootAccess = true,
        hasReadyCheckAccess = true,
        record = false,
        rollModel = {
            selectionAllowed = true,
            requiredWinnerCount = 1,
            resolution = {},
        },
        rolled = false,
    })
    local noAccess = FlowState.BuildState({
        canAwardSelection = true,
        canRoll = true,
        countdownRunning = false,
        currentFlowState = "loot",
        hasEligibleRaidReserve = true,
        hasItem = true,
        hasLootAccess = false,
        hasReadyCheckAccess = true,
        record = true,
        rollModel = {},
        rolled = false,
    })
    local noItemNoAccess = FlowState.BuildState({
        canAwardSelection = false,
        canRoll = false,
        countdownRunning = false,
        currentFlowState = "idle",
        hasEligibleRaidReserve = false,
        hasItem = false,
        hasLootAccess = false,
        hasReadyCheckAccess = true,
        record = false,
        rollModel = {},
        rolled = false,
    })

    assertEqual(ready.canStartRolls, true, "expected ready workflow to enable normal roll starts")
    assertEqual(ready.canStartSR, true, "expected ready workflow to enable SR when raid reserves are eligible")
    assertEqual(ready.canChangeItem, true, "expected ready workflow to allow item changes")
    assertEqual(ready.canAward, false, "expected ready workflow to block award before rolls exist")
    assertEqual(ready.canRollSelf, false, "expected ready workflow to block self-roll before countdown")
    assertEqual(ready.canReserveList, true, "expected ready workflow to allow reserve list access")
    assertEqual(ready.canSpamLoot, true, "expected ready workflow to allow spam loot")

    assertEqual(countdown.canStartRolls, false, "expected countdown workflow to block starting new rolls")
    assertEqual(countdown.canStartSR, false, "expected countdown workflow to block starting SR")
    assertEqual(countdown.canChangeItem, false, "expected countdown workflow to lock item changes")
    assertEqual(countdown.canAward, false, "expected countdown workflow to block awards")
    assertEqual(countdown.canRollSelf, true, "expected countdown workflow to allow local roll submission")

    assertEqual(awardReady.name, "award_ready", "expected winner-selected rolling workflow to be award-ready")
    assertEqual(awardReady.canAward, true, "expected award-ready workflow to allow awarding")

    assertTrue(noAccess.canStartRolls ~= true, "expected no-access workflow to block roll starts")
    assertEqual(noAccess.canReserveList, true, "expected no-access workflow to keep reserves UI available")
    assertTrue(noAccess.canSpamLoot ~= true, "expected no-access workflow to block spam loot")
    assertEqual(noItemNoAccess.canReserveList, true, "expected no-item no-access workflow to keep reserves UI available")
end)

test("master dropdown click uses UIDropDown owner/value arguments", function()
    local h = newHarness()
    local raid = {
        holder = nil,
        banker = nil,
        disenchanter = nil,
    }

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 1
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })

    h.addon.UnitIterator = function()
        local emitted = false
        return function()
            if emitted then
                return nil
            end
            emitted = true
            return "raid1"
        end
    end

    _G.UnitName = function(unit)
        if unit == "raid1" then
            return "Elenwen"
        end
        return nil
    end

    _G.GetRaidRosterInfo = function(index)
        if index == 1 then
            return "Elenwen", nil, 1
        end
        return nil
    end

    h.Database.GetRaidStoreOrNil = function()
        return {
            GetRaidByIndex = function(_, raidId)
                if raidId == 1 then
                    return raid
                end
                return nil
            end,
        }
    end

    local capturedSelectionInfo = nil
    _G.UIDropDownMenu_AddButton = function(info, level)
        if level == 2 and info and info.text == "Elenwen" then
            capturedSelectionInfo = info
        end
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)
    refreshMasterFrameForTest(Master)

    local holdDropDown = _G.KRTMasterHoldDropDown
    assertTrue(type(holdDropDown._initialize) == "function", "expected Hold dropdown to be initialized")
    UIDROPDOWNMENU_OPEN_MENU = holdDropDown
    UIDROPDOWNMENU_MENU_LEVEL = 2
    UIDROPDOWNMENU_MENU_VALUE = 1
    holdDropDown._initialize()

    assertTrue(capturedSelectionInfo ~= nil, "expected level-2 dropdown info for the raid member")

    local listButton = h.makeFrame(true, "DropDownList2Button4")
    capturedSelectionInfo.func(listButton, capturedSelectionInfo.arg1, capturedSelectionInfo.arg2)

    assertEqual(holdDropDown._dropdownText, "Elenwen", "expected dropdown text to use the selected player")
    assertEqual(holdDropDown._selectedValue, "Elenwen", "expected dropdown selected value to use the player")
    assertEqual(h.feature.lootState.holder, "Elenwen", "expected holder state to track dropdown selection")
    assertEqual(raid.holder, "Elenwen", "expected raid holder field to persist dropdown selection")
end)

test("master item count bindings use shared edit-box handlers", function()
    local h = newHarness()
    local refreshCount = 0

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end
    loadMasterFrameForTest(Master, frame)
    refreshMasterFrameForTest(Master)

    local itemCountBox = _G.KRTMasterItemCount
    assertTrue(type(itemCountBox.OnTextChanged) == "function", "expected OnTextChanged to be bound through UI.EditBoxes.BindHandlers")
    assertTrue(type(itemCountBox.OnEnterPressed) == "function", "expected OnEnterPressed to be bound through UI.EditBoxes.BindHandlers")
    assertTrue(type(itemCountBox.OnEditFocusLost) == "function", "expected OnEditFocusLost to be bound through UI.EditBoxes.BindHandlers")

    refreshCount = 0
    itemCountBox:OnTextChanged(true)
    itemCountBox:OnEnterPressed()
    itemCountBox:OnEditFocusLost()

    assertEqual(refreshCount, 3, "expected all shared edit-box handlers to request a refresh")
end)

test("master item selection popup stays clickable", function()
    local h = newHarness()
    local selectedIndex = nil
    local linkOne = h.registerItem(9401, "Popup Blade")
    local linkTwo = h.registerItem(9402, "Popup Axe")
    local items = {
        [1] = { itemLink = linkOne, itemName = "Popup Blade", itemTexture = "IconOne", count = 1 },
        [2] = { itemLink = linkTwo, itemName = "Popup Axe", itemTexture = "IconTwo", count = 2 },
    }

    h.addon.Services.Loot = {
        FetchLoot = function()
            h.feature.lootState.lootCount = 2
            h.feature.lootState.currentItemIndex = 1
        end,
        GetItem = function(index)
            return items[index]
        end,
        GetItemName = function(index)
            return items[index] and items[index].itemName or nil
        end,
        GetItemTexture = function(index)
            return items[index] and items[index].itemTexture or nil
        end,
        GetCurrentItemCount = function()
            return 1
        end,
        SelectItem = function(_, index)
            selectedIndex = index
        end,
        ItemExists = function(_, index)
            return items[index] ~= nil
        end,
    }
    h.addon.Services.Raid = {
        IsMasterLooter = function()
            return true
        end,
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    _G.UnitName = function(unit)
        if unit == "target" then
            return "Loot Target"
        end
        return unit
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)
    Master.EnsureUI = function()
        return frame
    end
    Master:LOOT_OPENED()
    Master._Private.BtnSelectItem(h.makeFrame(true, "ItemSelectInvoker"))

    local firstButton = _G.KRTMasterItemSelectionBtn1
    local secondButton = _G.KRTMasterItemSelectionBtn2

    assertTrue(firstButton ~= nil, "expected the selection popup to create the first selection button")
    assertTrue(secondButton ~= nil, "expected the selection popup to create the second selection button")
    assertTrue(type(firstButton.OnClick) == "function", "expected the created selection button to keep its click handler")

    firstButton:OnClick("LeftButton")

    assertEqual(selectedIndex, 1, "expected clicking the selection popup button to pick the corresponding loot index")
end)

test("master workflow model exposes compact session winners", function()
    local h = newHarness()

    h.addon.Services.Loot = {
        GetItem = function()
            return nil
        end,
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local SessionWinners = h.addon.Services.Master.SessionWinners
    local winners = SessionWinners.BuildModel({
        resolution = {
            autoWinners = {
                { name = "Alice", roll = 99 },
            },
            tiedNames = { "Bob", "Cara" },
            requiresManualResolution = true,
        },
    })

    assertEqual(#winners.rows, 3, "expected compact session winners to include automatic and tied candidates")
    assertEqual(winners.rows[1].name, "Alice", "expected automatic winner first")
    assertEqual(winners.rows[1].state, "auto", "expected automatic winner state")
    assertEqual(winners.rows[2].name, "Bob", "expected first tied candidate")
    assertEqual(winners.rows[2].state, "tied", "expected tied candidate state")
    assertEqual(winners.summaryText, "Winner: Alice; Tie: Bob, Cara", "expected compact winners summary text")
end)

test("master loot reserve ui state exposes reserved players", function()
    local h = newHarness()
    local link = h.registerItem(9410, "Reserved Popup Blade")
    local calls = {}

    h.addon.Services.Reserves = {
        HasItemReserves = function(itemId)
            return itemId == 9410
        end,
        GetPlayersForItem = function(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers)
            calls[#calls + 1] = {
                itemId = itemId,
                useColor = useColor,
                showPlus = showPlus,
                showMulti = showMulti,
                onlyCurrentRaidPlayers = onlyCurrentRaidPlayers,
            }
            if itemId == 9410 then
                return { "Gargull (x2)", "Emann" }
            end
            return {}
        end,
    }
    h.feature.Services = h.addon.Services

    loadMasterController(h)

    local state = h.addon.UI.Widgets.Call("LootHints", "BuildLootReserveUiState", link)

    assertTrue(state.hasReserves == true, "expected reserved loot state to be marked")
    assertEqual(state.itemId, 9410, "expected reserve state to expose item id")
    assertEqual(#state.playerLines, 2, "expected tooltip lines for every reserver")
    assertEqual(state.playerLines[1], "Gargull (x2)", "expected first reserver line")
    assertEqual(state.playerLines[2], "Emann", "expected second reserver line")
    assertEqual(calls[1].useColor, true, "expected tooltip reserver names to allow class color")
    assertEqual(calls[1].showPlus, true, "expected tooltip reserver names to keep plus values")
    assertEqual(calls[1].showMulti, true, "expected tooltip reserver names to keep multi counts")
    assertEqual(calls[1].onlyCurrentRaidPlayers, false, "expected tooltip to show all reservers")
end)

test("blizzard loot frame buttons show softres reserve hints", function()
    local h = newHarness()
    local reservedLink = h.registerItem(9411, "Corpse Reserve Blade")
    local otherLink = h.registerItem(9412, "Corpse Other Blade")
    local tooltipLines = {}

    h.addon.Options.AddNamespace("UI", {
        showTooltips = true,
    })
    h.addon.Services.Reserves = {
        HasItemReserves = function(itemId)
            return itemId == 9411
        end,
        GetPlayersForItem = function(itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers)
            if itemId == 9411 and useColor == true and showPlus == true and showMulti == true and onlyCurrentRaidPlayers == false then
                return { "Gargull (x2)", "Emann" }
            end
            return {}
        end,
    }
    h.feature.Services = h.addon.Services

    _G.LootFrame = h.makeFrame(true, "LootFrame")
    _G.LootButton1 = h.makeFrame(true, "LootButton1")
    _G.LootButton2 = h.makeFrame(true, "LootButton2")
    _G.LootButton1IconTexture = h.makeFrame(true, "LootButton1IconTexture")
    _G.LootButton2IconTexture = h.makeFrame(true, "LootButton2IconTexture")
    _G.LOOTFRAME_NUMBUTTONS = 2
    _G.GetNumLootItems = function()
        return 2
    end
    _G.GetLootSlotLink = function(slot)
        if slot == 1 then
            return reservedLink
        end
        if slot == 2 then
            return otherLink
        end
        return nil
    end
    _G.GameTooltip = {
        lines = tooltipLines,
        SetOwner = function(self, owner, anchor)
            self.owner = owner
            self.anchor = anchor
        end,
        SetHyperlink = function(self, itemLink)
            self.itemLink = itemLink
        end,
        AddLine = function(self, text)
            self.lines[#self.lines + 1] = text
        end,
        Show = function(self)
            self.shown = true
        end,
        Hide = function(self)
            self.hidden = true
        end,
    }

    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    Master:LOOT_OPENED()

    assertTrue(_G.LootButton1._krtLootReserveMarked == true, "expected reserved LootFrame button to be marked")
    assertEqual(#_G.LootButton1._krtLootReservePlayerLines, 2, "expected tooltip lines for each reserver")
    assertEqual(_G.LootButton1._krtLootReservePlayerLines[1], "Gargull (x2)", "expected first reserver line")
    assertTrue(type(_G.LootButton1.HookedOnEnter) == "function", "expected reserved LootFrame button to hook tooltip")
    assertTrue(_G.LootButton2._krtLootReserveMarked == false, "expected unreserved LootFrame button to be unmarked")

    _G.LootButton1:HookedOnEnter()

    assertEqual(_G.GameTooltip.itemLink, reservedLink, "expected tooltip to keep the LootFrame item hyperlink")
    assertEqual(tooltipLines[2], h.addon.L.StrLootReservedBy, "expected tooltip reserve heading")
    assertEqual(tooltipLines[3], "Gargull (x2)", "expected tooltip first reserver line")
    assertEqual(tooltipLines[4], "Emann", "expected tooltip second reserver line")
end)

test("master auto spam announces opened loot with softres lines only for reserved items", function()
    local h = newHarness()
    local reservedLink = h.registerItem(9431, "Reserved Auto Blade")
    local openLink = h.registerItem(9432, "Open Auto Blade")
    local items = {
        [1] = { itemLink = reservedLink, itemName = "Reserved Auto Blade", itemTexture = "IconReserved", count = 1 },
        [2] = { itemLink = openLink, itemName = "Open Auto Blade", itemTexture = "IconOpen", count = 1 },
    }

    h.addon.L.ChatSpamLootFrom = "%s dropped:"
    h.addon.L.ChatSpamLootReservedHeader = "Item reserved:"
    h.addon.L.ChatSpamLootReservedLine = "%d. %s by %s"
    h.addon.Options.AddNamespace("Master", {
        autoSpamLootOnLootOpened = false,
        autoSpamSoftResOnLootOpened = false,
    })
    setHarnessOption(h, "Master", "autoSpamLootOnLootOpened", true)
    setHarnessOption(h, "Master", "autoSpamSoftResOnLootOpened", true)
    h.addon.Services.Loot = {
        FetchLoot = function()
            h.feature.lootState.lootCount = 2
            h.feature.lootState.currentItemIndex = 1
        end,
        GetLootWindowItems = function()
            return items
        end,
        GetItem = function(index)
            return items[index]
        end,
        GetItemLink = function(index)
            return items[index] and items[index].itemLink or nil
        end,
        GetItemName = function(index)
            return items[index] and items[index].itemName or nil
        end,
        GetItemTexture = function(index)
            return items[index] and items[index].itemTexture or nil
        end,
        GetCurrentItemCount = function()
            return 1
        end,
        ItemExists = function(_, index)
            return items[index] ~= nil
        end,
    }
    h.addon.Services.Raid = {
        IsMasterLooter = function()
            return true
        end,
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
        _EnsureLootWindowItemContext = function()
            return nil
        end,
        NotifyLootWindowOpened = function()
            return true
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return true
        end,
        HasItemReserves = function(itemId)
            return itemId == 9431
        end,
        GetReserveCountForItem = function(itemId)
            return itemId == 9431 and 2 or 0
        end,
        FormatReservedPlayersLine = function(_, itemId, useColor, showPlus, showMulti, onlyCurrentRaidPlayers)
            assertEqual(useColor, false, "expected auto spam SoftRes lines to be chat-safe")
            assertEqual(showPlus, false, "expected auto spam SoftRes lines to hide Plus suffixes")
            assertEqual(showMulti, false, "expected auto spam SoftRes lines to hide multi-reserve suffixes")
            assertEqual(onlyCurrentRaidPlayers, true, "expected auto spam SoftRes lines to include current raid players only")
            if itemId == 9431 then
                return "Alice, Bob"
            end
            return ""
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    _G.UnitName = function(unit)
        if unit == "target" then
            return "Anub'Rekhan"
        end
        return nil
    end

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(false, "KRTMaster")

    _G.KRTMaster = frame
    Master.RequestRefresh = function() end
    Master.EnsureUI = function()
        return frame
    end

    Master:LOOT_OPENED()

    local output = table.concat(h.logs.info, "\n")
    local secondItemStart = string.find(output, "2. " .. openLink, 1, true)
    local reservedHeaderStart = string.find(output, h.addon.L.ChatSpamLootReservedHeader, 1, true)

    assertContains(h.logs.info, "Anub'Rekhan dropped:", "expected auto spam to announce the loot source name")
    assertContains(h.logs.info, "1. " .. reservedLink, "expected auto spam to announce the reserved item")
    assertContains(h.logs.info, "2. " .. openLink, "expected auto spam to announce the open item")
    assertContains(h.logs.info, h.addon.L.ChatSpamLootReservedHeader, "expected reserved items section after the loot list")
    assertContains(h.logs.info, "1. " .. reservedLink .. " by Alice, Bob", "expected reserved item line in the reserved section")
    assertTrue(secondItemStart and reservedHeaderStart and secondItemStart < reservedHeaderStart, "expected reserved section after the full loot list")
    assertTextNotContains(output, reservedLink .. " SoftRes:", "expected no inline SoftRes line for reserved item")
    assertTextNotContains(output, openLink .. " by", "expected no reserved-section line for item without reservers")
end)

test("master loot opened stays hidden while passively observing group loot", function()
    local h = newHarness()
    local link = h.registerItem(9441, "Passive Blade")
    local items = {
        [1] = { itemLink = link, itemName = "Passive Blade", itemTexture = "IconPassive", count = 1 },
    }

    h.addon.Services.Loot = {
        FetchLoot = function()
            h.feature.lootState.lootCount = 1
            h.feature.lootState.currentItemIndex = 1
        end,
        GetLootWindowItems = function()
            return items
        end,
        GetItem = function(index)
            return items[index]
        end,
        GetItemName = function(index)
            return items[index] and items[index].itemName or nil
        end,
        GetItemTexture = function(index)
            return items[index] and items[index].itemTexture or nil
        end,
        GetCurrentItemCount = function()
            return 1
        end,
        ItemExists = function(_, index)
            return items[index] ~= nil
        end,
    }
    h.addon.Services.Raid = {
        IsMasterLooter = function()
            return false
        end,
        CanObservePassiveLoot = function()
            return true
        end,
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
        _EnsureLootWindowItemContext = function()
            return nil
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = false,
    })

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(false, "KRTMaster")

    _G.KRTMaster = frame
    Master.RequestRefresh = function() end
    Master.EnsureUI = function()
        return frame
    end

    Master:LOOT_OPENED()

    assertTrue(not frame:IsShown(), "expected passive group loot observation not to auto-open the Master frame")
end)

test("master roll rows stay clickable through the shared list controller", function()
    local h = newHarness()

    h.addon.Services.Loot = {
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Rolls = {
        GetDisplayModel = function()
            return {
                rows = {
                    {
                        name = "Alice",
                        roll = 98,
                        selectionAllowed = true,
                    },
                },
                selectionAllowed = true,
                requiredWinnerCount = 1,
                resolution = {
                    autoWinners = {},
                    tiedNames = {},
                    requiresManualResolution = true,
                    topRollName = "Alice",
                },
            }
        end,
        GetRollSession = function()
            return { id = "session-1" }
        end,
        GetRollStatus = function()
            return h.rollTypes.MAINSPEC, true, false, false
        end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Modules/UI/ListController.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local rollListDirtyCount = 0
    local rollListUpdateCount = 0
    local rollListController = Master._rollListController
    local oldRollListDirty = rollListController and rollListController.Dirty or nil
    local oldRollListUpdateNow = rollListController and rollListController.UpdateNow or nil
    local frame = h.makeFrame(true, "KRTMaster")
    local suffixes = {
        "ConfigBtn",
        "SelectItemBtn",
        "SpamLootBtn",
        "MSBtn",
        "OSBtn",
        "SRBtn",
        "FreeBtn",
        "CountdownBtn",
        "AwardBtn",
        "RollBtn",
        "ClearBtn",
        "HoldBtn",
        "BankBtn",
        "DisenchantBtn",
        "Name",
        "RollsHeaderPlayer",
        "RollsHeaderInfo",
        "RollsHeaderCounter",
        "RollsHeaderRoll",
        "ReserveListBtn",
        "LootCounterBtn",
        "ItemCount",
        "HoldDropDown",
        "BankDropDown",
        "DisenchantDropDown",
        "ScrollFrame",
        "ScrollFrameScrollChild",
        "ItemBtn",
    }

    assertTrue(type(oldRollListDirty) == "function", "expected Master roll list controller to expose Dirty")
    assertTrue(type(oldRollListUpdateNow) == "function", "expected Master roll list controller to expose UpdateNow")

    function rollListController:Dirty()
        rollListDirtyCount = rollListDirtyCount + 1
        return oldRollListDirty(self)
    end

    function rollListController:UpdateNow()
        rollListUpdateCount = rollListUpdateCount + 1
        return oldRollListUpdateNow(self)
    end

    _G.KRTMaster = frame
    for i = 1, #suffixes do
        local name = "KRTMaster" .. suffixes[i]
        _G[name] = h.makeFrame(true, name)
    end
    _G.KRTMasterHoldDropDownButton = h.makeFrame(true, "KRTMasterHoldDropDownButton")
    _G.KRTMasterBankDropDownButton = h.makeFrame(true, "KRTMasterBankDropDownButton")
    _G.KRTMasterDisenchantDropDownButton = h.makeFrame(true, "KRTMasterDisenchantDropDownButton")

    Master.RequestRefresh = function() end
    loadMasterFrameForTest(Master, frame)
    refreshMasterFrameForTest(Master)

    assertTrue(rollListDirtyCount > 0, "expected first Master refresh to dirty the roll list")
    assertTrue(rollListUpdateCount > 0, "expected first Master refresh to update the roll list")

    local dirtyAfterFirstRefresh = rollListDirtyCount
    local updatesAfterFirstRefresh = rollListUpdateCount
    refreshMasterFrameForTest(Master)

    assertEqual(rollListDirtyCount, dirtyAfterFirstRefresh, "expected unchanged Master refresh to skip roll list dirtying")
    assertEqual(rollListUpdateCount, updatesAfterFirstRefresh, "expected unchanged Master refresh to skip roll list update")

    local row = _G.KRTMasterPlayerBtn1
    assertTrue(row ~= nil, "expected the shared list controller to create the first roll row")
    assertEqual(row.playerName, "Alice", "expected the created roll row to keep the player identity for click handling")
    assertTrue(type(row.OnClick) == "function", "expected the created roll row to keep an OnClick handler")

    row:OnClick()

    assertTrue(h.addon.UI.Selection.IsSelected("MLRollWinners", "Alice"), "expected clicking the rendered row to select the winner")
end)

test("master add-roll refreshes coalesce duplicate bursts", function()
    local h = newHarness()

    h.addon.Services.Loot = {
        ItemExists = function()
            return false
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Rolls = {
        GetDisplayModel = function()
            return { rows = {}, resolution = {} }
        end,
        GetRollSession = function()
            return { id = "session-1" }
        end,
        GetRollStatus = function()
            return h.rollTypes.MAINSPEC, true, false, false
        end,
        GetResolvedWinner = function()
            return nil
        end,
        ShouldUseTieReroll = function()
            return false
        end,
        SetExpectedWinners = function() end,
        EnsureLootRollSession = function()
            return { id = "session-1" }
        end,
        SyncSessionState = function() end,
        IsCountdownRunning = function()
            return false
        end,
        StopCountdown = function() end,
        StartCountdown = function() end,
        FinalizeRollSession = function() end,
    }
    h.addon.Services.Reserves = {
        HasData = function()
            return false
        end,
        HasItemReserves = function()
            return false
        end,
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Modules/UI/ListController.lua")
    h.feature.UI = h.addon.UI
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    local refreshCount = 0
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.Bus.TriggerEvent(h.addon.Events.Internal.AddRoll, "Alice", 98)
    h.Bus.TriggerEvent(h.addon.Events.Internal.AddRoll, "Bob", 97)

    assertEqual(refreshCount, 0, "expected add-roll burst to defer Master refresh")
    h:flushTimers()
    assertEqual(refreshCount, 1, "expected add-roll burst to request one Master refresh")
    assertEqual(Master._refreshHandle, nil, "expected coalesced Master refresh handle to clear after firing")
end)

test("manual exclusion blocks candidate eligibility and roll intake", function()
    local h = newHarness()
    local link = h.registerItem(9305, "Banblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    assertTrue(Rolls:SetManualExclusion("Alice", true) == true, "expected manual exclusion API to accept a valid player name")

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    assertTrue(eligibility ~= nil and eligibility.ok ~= true, "expected manually excluded player to fail candidate eligibility")
    assertEqual(eligibility.reason, "manual_exclusion", "expected manual exclusion to surface through the eligibility reason")

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    assertEqual(#Rolls:GetRolls(), 0, "expected manually excluded player to be blocked before raw roll intake")
end)

test("explicit pass stays visible without entering winner resolution", function()
    local h = newHarness()
    local link = h.registerItem(9306, "Passblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SetPlayerResponse("Alice", "PASS") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice
    local bob

    assertTrue(model.visibleRows == nil, "expected visibleRows filtering to become controller-owned, not service-owned")
    for i = 1, #(model.rows or {}) do
        local row = model.rows[i]
        if row.name == "Alice" then
            alice = row
        elseif row.name == "Bob" then
            bob = row
        end
    end

    assertEqual(model.resolution.autoWinners[1].name, "Bob", "expected pass responses to stay out of winner resolution")
    assertTrue(alice ~= nil, "expected explicit pass rows to remain materialized in the service model")
    assertTrue(bob ~= nil, "expected rolled rows to remain materialized in the service model")
    assertEqual(alice.name, "Alice", "expected explicit pass to stay materialized in the service model")
    assertEqual(alice.status, "PASS", "expected the current response status to remain PASS")
    assertEqual(alice.infoText, "PASS", "expected explicit pass rows to render the PASS tag")
    assertTrue(alice.roll == nil, "expected pass rows to keep the roll column empty")
    assertEqual(bob.name, "Bob", "expected the rolled player to stay visible after explicit passes")
end)

test("explicit pass can transition back into a valid roll while the session stays open", function()
    local h = newHarness()
    local link = h.registerItem(9310, "Passreturnblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SetPlayerResponse("Alice", "PASS") == true, "expected pass to be accepted while the session is open")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 88) == true, "expected pass responses to remain reversible into a valid roll")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice = model.rows[1]

    assertEqual(#Rolls:GetRolls(), 1, "expected the accepted post-pass roll to remain in the raw log")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the post-pass roll to return to winner resolution")
    assertEqual(alice.status, "ROLL", "expected the current response to move from PASS back to ROLL")
    assertEqual(alice.roll, 88, "expected the resumed roll to populate the displayed roll value")
    assertEqual(alice.infoText, "", "expected the pass marker to disappear after a valid roll")
end)

test("validate winner rejects explicit pass with a service-owned denial reason", function()
    local h = newHarness()
    local link = h.registerItem(9313, "Validatepassblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SetPlayerResponse("Alice", "PASS") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:SetRollRecordingEnabled(false)

    local validation = Rolls:ValidateWinner("Alice", link, h.rollTypes.MAINSPEC)

    assertTrue(validation.ok ~= true, "expected pass responses to stay out of winner validation")
    assertEqual(validation.reason, "player_pass", "expected winner validation to expose the explicit pass reason directly from the service")
    assertEqual(validation.warnMessage, "L.ErrMLWinnerPassed", "expected winner validation to include the user-facing denial message")
end)

test("cancelled response keeps raw roll history but leaves current resolution", function()
    local h = newHarness()
    local link = h.registerItem(9307, "Cancelblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    assertTrue(Rolls:SetPlayerResponse("Alice", "CANCELLED") == true, "expected cancel to retract an earlier explicit roll response")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice

    assertTrue(model.visibleRows == nil, "expected visibleRows filtering to become controller-owned, not service-owned")
    for i = 1, #(model.rows or {}) do
        local row = model.rows[i]
        if row.name == "Alice" then
            alice = row
            break
        end
    end

    assertEqual(#Rolls:GetRolls(), 2, "expected raw rolls to remain append-only after a cancel")
    assertEqual(model.resolution.autoWinners[1].name, "Bob", "expected cancelled rolls to leave the current winner resolution")
    assertTrue(alice ~= nil, "expected cancelled responses to stay materialized in the service model")
    assertEqual(alice.name, "Alice", "expected cancelled responses to stay materialized in the service model")
    assertEqual(alice.status, "CANCELLED", "expected the current response status to become CANCELLED")
    assertEqual(alice.infoText, "CXL", "expected cancelled responses to render the compact cancel tag")
    assertTrue(alice.roll == nil, "expected cancelled responses to clear the displayed roll value")
end)

test("validate winner allows non-roll assignment targets without an active roll response", function()
    local h = newHarness()
    local link = h.registerItem(9314, "Validateholdblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    local validation = Rolls:ValidateWinner("Banker", link, h.rollTypes.BANK)

    assertTrue(validation.ok == true, "expected non-roll assignment targets to validate through eligibility without requiring a roll response")
    assertEqual(validation.reason, nil, "expected valid non-roll assignment targets to carry no denial reason")
end)

test("cancelled responses can roll again while the session stays open", function()
    local h = newHarness()
    local link = h.registerItem(9311, "Cancelreturnblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SubmitDebugRoll("Alice", 98) == true, "expected the initial roll to be accepted")
    assertTrue(Rolls:SetPlayerResponse("Alice", "CANCELLED") == true, "expected cancel to retract the current roll response")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 91) == true, "expected cancelled responses to remain reversible into a valid roll")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice = model.rows[1]

    assertEqual(#Rolls:GetRolls(), 2, "expected raw roll history to remain append-only across cancel and reroll")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the rerolled response to re-enter winner resolution")
    assertEqual(alice.status, "ROLL", "expected the current response to move from CANCELLED back to ROLL")
    assertEqual(alice.roll, 91, "expected the new post-cancel roll to become the active displayed roll")
    assertEqual(alice.infoText, "", "expected the cancel marker to disappear after a valid reroll")
end)

test("timed out responses stay terminal for the current session", function()
    local h = newHarness()
    local link = h.registerItem(9312, "Timeoutblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function(itemId, name)
            if itemId == 9312 and name == "Alice" then
                return 1
            end
            return 0
        end,
        GetPlayersForItem = function(itemId)
            if itemId == 9312 then
                return { "Alice" }
            end
            return {}
        end,
    }
    h.feature.Services = h.addon.Services
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.RESERVED

    Rolls:SetRollRecordingEnabled(true)
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local alice = model.rows[1]
    local ok, reason = Rolls:SubmitDebugRoll("Alice", 87)

    assertEqual(alice.status, "TIMED_OUT", "expected inactive seeded candidates to become TIMED_OUT on close")
    assertTrue(ok ~= true, "expected timed-out responses to reject late rolls for the same session")
    assertEqual(reason, "record_inactive", "expected late rolls after timeout to stay blocked by the closed session")
end)

test("tie reroll resets intake to tied players only", function()
    local h = newHarness()
    local link = h.registerItem(9307, "Tieblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 98")
    Rolls:CHAT_MSG_SYSTEM("Cara 77")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    assertTrue(model.resolution.requiresManualResolution == true, "expected a first-place tie to require manual resolution before reroll")
    assertTrue(Rolls:BeginTieReroll(model.resolution.tiedNames) == true, "expected tied winners to reopen the current session as a reroll")

    model = Rolls:GetDisplayModel()
    assertEqual(#Rolls:GetRolls(), 0, "expected tie reroll to clear previous raw rolls")
    assertEqual(model.rows[1].name, "Alice", "expected the full model to keep tied players materialized")
    assertEqual(model.rows[2].name, "Bob", "expected the full model to keep tied players materialized")
    assertTrue(model.rows[3] == nil, "expected the full model to drop non-tied players from the reroll pool")
    assertTrue(model.visibleRows == nil, "expected frame-facing filtering to stop living in the rolls service model")

    local blocked = Rolls:GetCandidateEligibility("Cara", link, h.rollTypes.MAINSPEC)
    assertEqual(blocked.reason, "reroll_filtered", "expected non-tied players to become ineligible during the tie reroll")

    Rolls:CHAT_MSG_SYSTEM("Cara 88")
    assertEqual(#Rolls:GetRolls(), 0, "expected reroll-filtered players to stay blocked from raw roll intake")

    Rolls:CHAT_MSG_SYSTEM("Alice 91")
    assertEqual(#Rolls:GetRolls(), 1, "expected tied players to remain eligible during the reroll")
end)

test("duplicate roll attempts stay visible on the accepted response row", function()
    local h = newHarness()
    local link = h.registerItem(9309, "Duplicateblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:SetRollRecordingEnabled(true)
    assertTrue(Rolls:SubmitDebugRoll("Alice", 98) == true, "expected the first roll to be accepted")
    local ok, reason = Rolls:SubmitDebugRoll("Alice", 77)
    assertTrue(ok ~= true, "expected the duplicate roll to be denied")
    assertEqual(reason, "roll_limit", "expected duplicate roll denial to carry the roll-limit reason")

    local model = Rolls:GetDisplayModel()
    local alice = model.rows[1]

    assertEqual(#Rolls:GetRolls(), 1, "expected duplicate attempts to stay out of raw roll intake")
    assertEqual(alice.name, "Alice", "expected accepted roller to stay visible")
    assertEqual(alice.roll, 98, "expected accepted best roll to remain unchanged")
    assertEqual(alice.outOfFlowReason, "roll_limit", "expected row to expose the duplicate denial reason")
    assertEqual(alice.outOfFlowCount, 1, "expected row to count duplicate attempts")
    assertEqual(alice.outOfFlowLastRoll, 77, "expected row to expose the last ignored duplicate roll")
    assertEqual(alice.outOfFlowLastReason, "roll_limit", "expected row to expose the last ignored duplicate reason")
    assertEqual(alice.outOfFlowLastSource, "debug_roll", "expected row to expose the last ignored duplicate source")
    assertEqual(alice.outOfFlowText, nil, "expected duplicate detail text to stay out of the display model")
    assertEqual(alice.infoText, "DUP", "expected row info to flag duplicate attempts")
    assertEqual(model.outOfFlowCount, 1, "expected model to summarize out-of-flow attempts")
end)

test("master award button triggers reroll for single-select ties", function()
    local h = newHarness()
    local link = h.registerItem(9308, "Mastertieblade")
    local rerollNames
    local refreshCount = 0
    local distributionStates = {}

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
        end,
        SetDistributionState = function(_, kind, payload)
            distributionStates[#distributionStates + 1] = {
                kind = kind,
                payload = payload,
            }
            return true
        end,
    }
    h.addon.Services.Rolls = {
        GetDisplayModel = function()
            return {
                pickMode = true,
                msCount = 0,
                requiredWinnerCount = 1,
                winner = nil,
                resolution = {
                    requiresManualResolution = true,
                    tiedNames = { "Alice", "Bob" },
                },
            }
        end,
        BeginTieReroll = function(_, names)
            rerollNames = names
            return true, names
        end,
        GetHighestRoll = function()
            return 98
        end,
        GetRollSession = function()
            return nil
        end,
        SyncSessionState = function() end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h.feature.RAID_TARGET_MARKERS = h.C.RAID_TARGET_MARKERS
    loadMasterController(h)

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = 2
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    assertTrue(Master._Private.BtnAward() == true, "expected single-select tie to trigger a reroll flow")
    assertEqual(rerollNames[1], "Alice", "expected tie reroll to receive the tied players in order")
    assertEqual(rerollNames[2], "Bob", "expected tie reroll to receive the tied players in order")
    assertEqual(distributionStates[1].kind, "tie_start", "expected tie reroll to publish tied names before reopening the roll")
    assertEqual(distributionStates[1].payload.names[1], "Alice", "expected tie-start distribution to include Alice")
    assertEqual(distributionStates[1].payload.names[2], "Bob", "expected tie-start distribution to include Bob")
    assertEqual(distributionStates[2].kind, "roll_start", "expected tie reroll to publish the reopened roll after tie state")
    assertEqual(refreshCount, 1, "expected tie reroll to request a UI refresh")
end)

test("master blocks award when manual resolution selection is incomplete", function()
    local ctx = setupMasterAwardHarness({
        selectedItemCount = 2,
        model = {
            rows = {
                makeMasterRollRow("Alice", 98, "ROLL", true),
                makeMasterRollRow("Bob", 77, "ROLL", true),
            },
            selectionAllowed = true,
            requiredWinnerCount = 2,
            resolution = {
                autoWinners = {},
                tiedNames = { "Alice", "Bob" },
                requiresManualResolution = true,
                topRollName = "Alice",
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok ~= true, "expected award to stay blocked until manual multi-pick is complete")
    assertEqual(#ctx.givenLoot, 0, "expected blocked award flow to avoid calling GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected blocked award flow to avoid queuing a pending award")
    assertEqual(#ctx.validationCalls, 0, "expected incomplete manual resolution to stop before winner revalidation")
    assertContains(ctx.h.logs.warn, "L.ErrMLWinnerTieUnresolved", "expected controller to warn when required winners are not fully selected")
end)

test("master does not synthesize winners from PASS CANCELLED or TIMED_OUT rows", function()
    local ctx = setupMasterAwardHarness({
        model = {
            rows = {
                makeMasterRollRow("Alice", nil, "PASS", true),
                makeMasterRollRow("Bob", nil, "CANCELLED", true),
                makeMasterRollRow("Cara", nil, "TIMED_OUT", false),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {},
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = nil,
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok ~= true, "expected non-roll rows to stay outside the award path")
    assertEqual(#ctx.givenLoot, 0, "expected PASS/CANCELLED/TIMED_OUT rows to never award loot")
    assertEqual(#ctx.queuedAwards, 0, "expected PASS/CANCELLED/TIMED_OUT rows to never queue an award")
    assertEqual(#ctx.validationCalls, 0, "expected controller to avoid winner validation when no resolver winner exists")
    assertContains(ctx.h.logs.warn, "L.ErrNoWinnerSelected", "expected controller to report that no valid winner is currently selected")
end)

test("master revalidates the suggested winner before awarding loot", function()
    local ctx = setupMasterAwardHarness({
        rollsByName = {
            Bob = 98,
        },
        getEligibility = function(playerName)
            if playerName == "Bob" then
                return {
                    ok = false,
                    reason = "manual_exclusion",
                }
            end
            return { ok = true }
        end,
        model = {
            rows = {
                makeMasterRollRow("Bob", 98, "ROLL", true),
            },
            selectionAllowed = false,
            requiredWinnerCount = 1,
            resolution = {
                autoWinners = {
                    { name = "Bob", roll = 98 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Bob",
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok ~= true, "expected controller to reject ineligible suggested winners at award time")
    assertEqual(#ctx.validationCalls, 1, "expected controller to consult Rolls:ValidateWinner before awarding")
    assertEqual(ctx.validationCalls[1].playerName, "Bob", "expected award-time revalidation to target the suggested winner")
    assertEqual(#ctx.givenLoot, 0, "expected excluded winners to never reach GiveMasterLoot")
    assertEqual(#ctx.queuedAwards, 0, "expected excluded winners to never queue pending awards")
    assertContains(ctx.h.logs.warn, "L.ErrMLWinnerExcluded", "expected the manual exclusion denial to surface through the controller warning path")
end)

test("master honors row selectionAllowed from the rolls service contract", function()
    local ctx = setupMasterAwardHarness({
        fromInventory = true,
        selectedItemCount = 2,
        rollsByName = {
            Alice = 98,
            Bob = 77,
        },
        model = {
            rows = {
                makeMasterRollRow("Alice", 98, "ROLL", true, false),
                makeMasterRollRow("Bob", 77, "ROLL", true, false),
            },
            selectionAllowed = true,
            requiredWinnerCount = 2,
            resolution = {
                autoWinners = {
                    { name = "Alice", roll = 98 },
                    { name = "Bob", roll = 77 },
                },
                tiedNames = {},
                requiresManualResolution = false,
                topRollName = "Alice",
            },
        },
    })

    local ok = ctx.Master._Private.BtnAward()

    assertTrue(ok ~= true, "expected controller to treat service-disabled rows as not selectable")
    assertEqual(#ctx.givenLoot, 0, "expected unselectable rows to stay out of the award flow")
    assertEqual(#ctx.queuedAwards, 0, "expected unselectable rows to avoid pending award creation")
    assertContains(ctx.h.logs.warn, "Diag.W.ErrMLMultiSelectNotEnough", "expected inventory multi-award to report missing selectable winners")
end)

test("row info tags stay separate from counter values", function()
    local h = newHarness()
    local link = h.registerItem(9309, "InfoColumnBlade")
    local playerInRaid = true

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function(_, playerName)
            if playerName == "Alice" then
                return 2
            end
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            if playerName and playerInRaid then
                return "raid1"
            end
            return "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.addon.Options
        .AddNamespace("LootCounter", {
            showLootCounterDuringMSRoll = false,
        })
        :Set("showLootCounterDuringMSRoll", true)

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:SetRollRecordingEnabled(false)

    playerInRaid = false
    local model = Rolls:GetDisplayModel()
    local first = model and model.rows and model.rows[1]

    assertTrue(first ~= nil, "expected rolled player to stay visible after leaving raid")
    assertEqual(first.counterText, "+2", "expected loot counter data to stay isolated in the counter column")
    assertEqual(first.infoText, "OUT", "expected row state to move into the dedicated info column")
end)

test("inventory winner stays undecorated in the pure rolls service model", function()
    local h = newHarness()
    local link = h.registerItem(9302, "Tradeblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    local first = model and model.rows and model.rows[1]

    assertEqual(h.addon.UI.Selection.GetCount("MLRollWinners"), 0, "expected inventory flow to keep the winner outside the loot-window multiselect")
    assertTrue(first ~= nil, "expected at least one rendered roll row")
    assertEqual(first.name, "Alice", "expected the top roller to stay first in the display model")
    assertTrue(first.displayName == nil, "expected the pure rolls service model to stop applying UI selection markers")
    assertTrue(first.isSelected == nil, "expected the pure rolls service model to stop marking selected rows")
    assertTrue(first.isFocused == nil, "expected the pure rolls service model to stop marking focused rows")
end)

test("inventory multi winners stay undecorated in the pure rolls service model", function()
    local h = newHarness()
    local link = h.registerItem(9303, "Twintradeblade")

    h.addon.Services.Loot = {
        GetItem = function(index)
            if index ~= 1 then
                return nil
            end
            return { itemLink = link }
        end,
    }
    h.addon.Services.Raid = {
        ClearRaidIcons = function() end,
        GetPlayerCount = function()
            return 0
        end,
        GetPlayerClass = function()
            return "MAGE"
        end,
        GetUnitID = function(_, playerName)
            return playerName and "raid1" or "none"
        end,
    }
    h.addon.Services.Reserves = {
        GetReserveCountForItem = function()
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.Deformat = function(msg)
        local name, roll = string.match(msg or "", "^(%a+)%s+(%d+)$")
        if not name then
            return nil
        end
        return name, tonumber(roll), 1, 100
    end
    _G.RANDOM_ROLL_RESULT = "%s %d"

    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.UI = h.addon.UI
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:SetRollRecordingEnabled(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:CHAT_MSG_SYSTEM("Cara 45")
    Rolls:SetRollRecordingEnabled(false)

    local model = Rolls:GetDisplayModel()
    assertEqual(h.addon.UI.Selection.GetCount("MLRollWinners"), 0, "expected Rolls service to stop prefiling inventory multi-copy multiselect state")
    assertTrue(model.rows[1].displayName == nil, "expected the pure rolls service model to omit UI display-name decoration")
    assertTrue(model.rows[2].displayName == nil, "expected the pure rolls service model to omit UI display-name decoration")
    assertEqual(h.feature.lootState.winner, nil, "expected Rolls service to stop mutating the primary inventory winner directly")
end)

test("inventory multi self-keep consumes one item and advances to the next winner", function()
    local ctx = setupInventoryTradeHarness({
        "Tester",
        "Alice",
    }, {
        Tester = 98,
        Alice = 77,
    })

    assertTrue(ctx.Master._Private.BtnAward() == true, "expected self-keep trade step to complete")
    assertEqual(#ctx.initiatedTrades, 0, "expected self-keep to avoid opening a trade window")
    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected self-keep to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Alice", "expected self-keep to advance to the next selected winner")
    assertEqual(ctx.h.addon.UI.Selection.GetCount("MLRollWinners"), 1, "expected self-keep to remove the completed winner from multiselect")
    assertEqual(#ctx.addCounts, 1, "expected one LootCounter increment for the completed winner")
    assertEqual(ctx.addCounts[1].name, "Tester", "expected self-keep to credit the trader as the completed winner")
    assertEqual(ctx.addCounts[1].count, 1, "expected self-keep to credit exactly one awarded item")
    assertEqual(#ctx.loggerRequests, 1, "expected self-keep to log the completed inventory award")
    assertEqual(ctx.loggerRequests[1].looter, "Tester", "expected self-keep logger update to use the trader winner")
    assertEqual(ctx.loggerRequests[1].source, "TRADE_KEEP", "expected self-keep logger update to use the keep source")
    assertEqual(ctx.getClearLootCount(), 0, "expected multi-step self-keep to preserve the current item")
    assertTrue(ctx.getClearIconsCount() >= 1, "expected self-keep flow to refresh raid icons for the remaining winners")
end)

test("inventory multi trade completion consumes one item and advances like self-keep", function()
    local ctx = setupInventoryTradeHarness({
        "Alice",
        "Tester",
    }, {
        Alice = 98,
        Tester = 77,
    })

    assertTrue(ctx.Master._Private.BtnAward() == true, "expected trade step to be accepted")
    assertEqual(#ctx.initiatedTrades, 1, "expected non-trader winner to open a trade")
    assertEqual(ctx.initiatedTrades[1], "Alice", "expected the first selected non-trader winner to receive the trade")
    assertEqual(ctx.h.feature.lootState.itemTraded, nil, "expected trade progress to wait for TRADE_ACCEPT_UPDATE before consuming")

    ctx.bagItems[0][1] = nil
    ctx.Master:TRADE_ACCEPT_UPDATE(1, 1)

    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected trade completion to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Tester", "expected trade completion to advance to the remaining selected winner")
    assertEqual(ctx.h.addon.UI.Selection.GetCount("MLRollWinners"), 1, "expected trade completion to remove the completed winner from multiselect")
    assertEqual(#ctx.addCounts, 1, "expected one LootCounter increment after trade completion")
    assertEqual(ctx.addCounts[1].name, "Alice", "expected trade completion to credit the traded winner")
    assertEqual(ctx.addCounts[1].count, 1, "expected trade completion to credit exactly one awarded item")
    assertEqual(#ctx.loggerRequests, 1, "expected one logger update after trade acceptance")
    assertEqual(ctx.loggerRequests[1].looter, "Alice", "expected trade completion logger update to use the traded winner")
    assertEqual(ctx.loggerRequests[1].source, "TRADE_ACCEPT", "expected trade completion logger update to use the accept source")
    assertEqual(ctx.getClearLootCount(), 0, "expected multi-step trade completion to preserve the current item until all winners are done")
end)

test("reserves import accepts Base64 encoded RaidRes JSON", function()
    local h = newHarness()
    local json = table.concat({
        '{"metadata":{"id":"ABC123","origin":"raidres"},',
        '"softreserves":[',
        '{"name":"Alice","role":"caster","items":[{"id":1201,"quality":4,"sr_plus":2},{"id":1201,"quality":4,"sr_plus":2}]},',
        '{"name":"Bob","role":"melee","items":[{"id":1301,"quality":3}]}',
        '],"hardreserves":[{"id":1401,"quality":4}]}',
    })

    _G.KRT_Reserves = {}
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local encoded = h.addon.Base64.Encode(json)
    local parsed = h.addon.Services.Reserves:ParseImport(encoded, "multi")

    assertTrue(type(parsed) == "table", "expected encoded JSON import to parse")
    assertEqual(parsed.format, "encoded-json", "expected encoded import format marker")
    assertEqual(parsed.nPlayers, 2, "expected two reserve players")
    assertEqual(parsed.reservesData.alice.reserves[1].rawID, 1201, "expected Alice item id")
    assertEqual(parsed.reservesData.alice.reserves[1].quantity, 2, "expected duplicate item to aggregate quantity")
    assertEqual(parsed.reservesData.alice.reserves[1].plus, 2, "expected sr_plus to map to plus")
    assertEqual(parsed.reservesData.alice.reserves[1].spec, "caster", "expected role to map to spec")
    assertEqual(parsed.reservesData.bob.reserves[1].rawID, 1301, "expected Bob item id")
end)

test("reserves import accepts Gargul zlib encoded SoftRes JSON", function()
    local h = newHarness()
    local json = table.concat({
        '{"metadata":{"id":"GARGUL1","origin":"softres.it","url":"https://softres.it/raid/GARGUL1"},',
        '"softreserves":[',
        '{"name":"Alice","class":"mage","plusOnes":1,"items":[{"id":1201,"quality":4}]}',
        '],"hardreserves":[]}',
    })

    _G.KRT_Reserves = {}
    h:load("!KRT/Libs/LibStub/LibStub.lua")
    h:load("!KRT/Libs/LibDeflate/LibDeflate.lua")
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [1201] = {
            { npcId = 16061, npcName = "Instructor Razuvious", raid = "Naxxramas", kind = "boss" },
        },
    })
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local lib = _G.LibStub("LibDeflate")
    local encoded = h.addon.Base64.Encode(lib:CompressZlib(json))
    local parsed = h.addon.Services.Reserves:ParseImport(encoded, "multi", { format = "json" })

    assertTrue(type(parsed) == "table", "expected Gargul zlib/Base64 SoftRes import to parse")
    assertEqual(parsed.format, "encoded-json", "expected Gargul import to use encoded JSON path")
    assertEqual(parsed.sourceId, "GARGUL1", "expected Gargul metadata id to be preserved")
    assertEqual(parsed.sourceOrigin, "softres.it", "expected Gargul metadata origin to be preserved")
    assertEqual(parsed.nPlayers, 1, "expected one Gargul reserve player")
    assertEqual(parsed.reservesData.alice.reserves[1].rawID, 1201, "expected Gargul item id")
    assertEqual(parsed.reservesData.alice.reserves[1].plus, 1, "expected Gargul plusOnes to map to plus")
    assertEqual(parsed.reservesData.alice.reserves[1].source, nil, "expected Gargul import to avoid boss grouping for JSON data")
end)

test("reserves import keeps plain CSV behavior before encoded fallback", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local csv = table.concat({
        '"item","itemid","from","name","class","spec","note","plus"',
        '"Coldsteel",1201,"Naxx","Alice","MAGE","Arcane","main",4',
    }, "\n")
    local parsed = h.addon.Services.Reserves:ParseImport(csv, "plus")

    assertTrue(type(parsed) == "table", "expected CSV import to still parse")
    assertEqual(parsed.format, nil, "expected CSV import not to be marked encoded JSON")
    assertEqual(parsed.mode, "plus", "expected CSV-selected mode to remain intact")
    assertEqual(parsed.reservesData.alice.reserves[1].rawID, 1201, "expected CSV row item id")
    assertEqual(parsed.reservesData.alice.reserves[1].plus, 4, "expected CSV plus value")
end)

test("reserves import explicit format prevents cross-format fallback", function()
    local h = newHarness()
    local json = table.concat({
        '{"metadata":{"id":"FORMAT1","origin":"raidres"},',
        '"softreserves":[{"name":"Alice","items":[{"id":1201,"quality":4}]}]}',
    })

    _G.KRT_Reserves = {}
    h:load("!KRT/Modules/Base64.lua")
    h:load("!KRT/Modules/Json.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")

    local encoded = h.addon.Base64.Encode(json)
    local csv = table.concat({
        '"item","itemid","from","name","class","spec","note","plus"',
        '"Coldsteel",1201,"Naxx","Alice","MAGE","Arcane","main",4',
    }, "\n")
    local parsedJson = h.addon.Services.Reserves:ParseImport(encoded, "multi", { format = "json" })
    local parsedCsv = h.addon.Services.Reserves:ParseImport(csv, "plus", { format = "csv" })
    local wrongCsvAsJson, csvAsJsonReason = h.addon.Services.Reserves:ParseImport(csv, "multi", { format = "json" })
    local wrongJsonAsCsv, jsonAsCsvReason = h.addon.Services.Reserves:ParseImport(encoded, "multi", { format = "csv" })

    assertTrue(type(parsedJson) == "table", "expected explicit JSON format to parse encoded RaidRes JSON")
    assertEqual(parsedJson.format, "encoded-json", "expected explicit JSON import to preserve encoded marker")
    assertTrue(type(parsedCsv) == "table", "expected explicit CSV format to parse CSV")
    assertEqual(parsedCsv.format, nil, "expected explicit CSV import not to be marked encoded JSON")
    assertEqual(wrongCsvAsJson, nil, "expected JSON-selected import to reject CSV text")
    assertEqual(csvAsJsonReason, "JSON_INVALID", "expected CSV text rejected as invalid encoded JSON")
    assertEqual(wrongJsonAsCsv, nil, "expected CSV-selected import to reject encoded JSON")
    assertEqual(jsonAsCsvReason, "NO_ROWS", "expected encoded JSON rejected as missing CSV rows")
end)

test("reserves import query and render hot paths record perf measurements", function()
    local h = newHarness()
    _G.KRT_Reserves = {}

    local perfRows = {}
    h.addon.hasPerf = true
    h.addon._PerfStart = function()
        return #perfRows + 1
    end
    h.addon._PerfFinish = function(_, label, startedAt, details)
        perfRows[#perfRows + 1] = {
            label = label,
            startedAt = startedAt,
            details = details,
        }
    end

    h:load("!KRT/Services/Reserves.lua")
    local Reserves = h.addon.Services.Reserves
    local csv = table.concat({
        '"item","itemid","from","name","class","spec","note","plus"',
        '"Coldsteel",1201,"Naxx","Alice","MAGE","Arcane","main",4',
        '"Frost Edge",1301,"Naxx","Bob","WARRIOR","Arms","off",1',
    }, "\n")

    local parsed = Reserves:ParseImport(csv, "plus", { format = "csv" })
    assertTrue(type(parsed) == "table", "expected CSV import to parse")
    local ok = Reserves:ApplyImport(parsed, nil, { silentInfo = true, reason = "perf_test" })
    assertTrue(ok == true, "expected parsed reserves to apply")

    Reserves:GetDisplayList()
    Reserves:QueryMissingItems(true)
    Reserves:GetReadinessReport(1201)

    local function findPerf(label, detail)
        for i = 1, #perfRows do
            local row = perfRows[i]
            if row.label == label and (not detail or tostring(row.details or ""):find(detail, 1, true)) then
                return row
            end
        end
        return nil
    end

    local function assertPerf(label, detail)
        local row = findPerf(label, detail)
        assertTrue(row ~= nil, "expected " .. label .. " perf measurement with " .. tostring(detail))
    end

    assertPerf("Reserves.ParseImport", "players=2")
    assertPerf("Reserves.ApplyImport", "players=2")
    assertPerf("Reserves.GetDisplayList", "rows=2")
    assertPerf("Reserves.QueryItemInfo", "item=1201")
    assertPerf("Reserves.QueryMissingItems", "missing=2")
    assertPerf("Reserves.GetReadinessReport", "item=1201")
end)

test("reserves import applies parsed reserves in chunks", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    local parsed = {
        mode = "multi",
        nPlayers = 3,
        importStats = { validRows = 3, skippedRows = 0 },
        reservesData = {
            alice = {
                playerNameDisplay = "Alice",
                reserves = {
                    { rawID = 1201, quantity = 1, plus = 0 },
                },
            },
            bob = {
                playerNameDisplay = "Bob",
                reserves = {
                    { rawID = 1301, quantity = 1, plus = 0 },
                },
            },
            cara = {
                playerNameDisplay = "Cara",
                reserves = {
                    { rawID = 1401, quantity = 1, plus = 0 },
                },
            },
        },
    }

    local callbackCount = 0
    local callbackOk
    local callbackPlayers
    local handle = Reserves:RequestApplyImport(parsed, nil, function(ok, nPlayers)
        callbackCount = callbackCount + 1
        callbackOk = ok
        callbackPlayers = nPlayers
    end, { silentInfo = true, reason = "chunk_import_test", chunkSize = 1, delaySeconds = 0 })

    assertEqual(h.timerCount(), 1, "expected chunked reserves import apply to schedule work")
    assertEqual(callbackCount, 0, "expected chunked reserves import callback to wait for scheduled chunks")
    assertTrue(Reserves:HasData() == false, "expected chunked reserves import not to publish data inline")

    local guard = 0
    while h.timerCount() > 0 and guard < 20 do
        h:flushTimers()
        guard = guard + 1
    end

    assertEqual(callbackCount, 1, "expected chunked reserves import callback to run once")
    assertTrue(callbackOk == true, "expected chunked reserves import callback to report success")
    assertEqual(callbackPlayers, 3, "expected chunked reserves import to report imported player count")
    assertTrue(handle:IsCancelled() == true, "expected completed chunked reserves import handle to become inactive")
    assertTrue(Reserves:HasData() == true, "expected chunked reserves import to publish reserve data")
    assertTrue(Reserves:HasItemReserves(1201) == true, "expected chunked reserves import to rebuild item indexes")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].rawID, 1201, "expected chunked reserves import to persist Alice reserve")
    assertEqual(_G.KRT_Reserves.Bob.reserves[1].rawID, 1301, "expected chunked reserves import to persist Bob reserve")
    assertEqual(_G.KRT_Reserves.Cara.reserves[1].rawID, 1401, "expected chunked reserves import to persist Cara reserve")
end)

test("reserves item-info updates coalesce into a single refresh", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001 },
                { rawID = 1002 },
            },
        },
    }
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves
    Service:Load()

    local updated, missingCount = Service:QueryMissingItems(true)
    assertTrue(updated ~= true, "expected initial query to leave items pending")
    assertEqual(missingCount, 2, "expected both uncached items to be pending")
    assertEqual(h.timerCount(), 0, "expected no timer before items resolve")

    h.registerItem(1001, "Coldsteel Dagger")
    h.registerItem(1002, "Frost Edge")

    assertTrue(Service:QueryItemInfo(1001) == true, "expected first pending item to resolve")
    assertEqual(h.timerCount(), 1, "expected first resolved item to schedule one batched refresh")
    assertEqual(h.Bus._triggered[h.addon.Events.Internal.ReservesDataChanged] or 0, 0, "expected no refresh event before batch completes")

    assertTrue(Service:QueryItemInfo(1002) == true, "expected second pending item to resolve")
    assertEqual(h.timerCount(), 0, "expected final batch flush to cancel pending timer")
    assertEqual(h.Bus._triggered[h.addon.Events.Internal.ReservesDataChanged] or 0, 1, "expected one coalesced reserves refresh event")

    local displayList = Service:GetDisplayList()
    assertEqual(#displayList, 2, "expected both resolved reserve items in display list")
end)

test("reserves item-info query refreshes display after async item cache resolves", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1301 },
            },
        },
    }

    h:load("!KRT/Modules/Item.lua")
    h.feature.Item = h.addon.Item
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves
    Service:Load()

    local updated, missingCount = Service:QueryMissingItems(true)
    assertTrue(updated ~= true, "expected uncached reserve item to stay pending")
    assertEqual(missingCount, 1, "expected one uncached reserve item")
    assertEqual(h.timerCount(), 1, "expected reserves to schedule shared item-cache polling")

    h.registerItem(1301, "Async Reserve Blade")
    h:flushTimers()

    assertEqual(h.timerCount(), 0, "expected async item-cache polling to drain after resolution")
    assertEqual(h.Bus._triggered[h.addon.Events.Internal.ReservesDataChanged] or 0, 1, "expected async item data to refresh reserves once")

    local displayList = Service:GetDisplayList()
    assertEqual(displayList[1].itemName, "Async Reserve Blade", "expected display list to use async item metadata")
    assertTrue(type(displayList[1].itemLink) == "string" and displayList[1].itemLink:find("item:1301", 1, true) ~= nil, "expected display list to use async item link")
end)

test("reserves display list exposes global item groups with structured player rows", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            playerNameDisplay = "Alice",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 2, plus = 4, class = "mage", source = "Boss A" },
            },
        },
        Bob = {
            playerNameDisplay = "Bob",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 1, plus = 1, class = "WARRIOR", source = "Boss B" },
            },
        },
    }
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")

    local function findPlayer(row, name)
        for i = 1, #(row and row.players or {}) do
            local player = row.players[i]
            if player and player.name == name then
                return player
            end
        end
        return nil
    end

    local Service = h.addon.Services.Reserves
    Service:Load()

    local displayList = Service:GetDisplayList()
    assertEqual(#displayList, 1, "expected matching item ids from different sources to share one global item group")

    local group = displayList[1]
    assertEqual(group.itemId, 1201, "expected item group to expose item id")
    assertEqual(group.itemName, "Coldsteel Dagger", "expected item group to expose item name")
    assertTrue(type(group.players) == "table", "expected item group to expose structured player rows")
    assertEqual(#group.players, 2, "expected both reserving players under one item group")

    local alice = findPlayer(group, "Alice")
    local bob = findPlayer(group, "Bob")
    assertTrue(alice ~= nil, "expected Alice player row")
    assertTrue(bob ~= nil, "expected Bob player row")
    assertEqual(alice.displayName, "Alice", "expected player row display name")
    assertEqual(alice.class, "MAGE", "expected normalized player row class token")
    assertEqual(alice.classColor, "ff40c7eb", "expected normalized player row class color")
    assertEqual(alice.quantity, 2, "expected player row quantity")
    assertEqual(alice.plus, 4, "expected player row plus")
    assertEqual(alice.checked, true, "expected player row checked state")
    assertEqual(bob.quantity, 1, "expected Bob quantity")
    assertEqual(bob.plus, 1, "expected Bob plus")
end)

test("reserves display rebuild reuses item row tables", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 1 },
                { rawID = 1301, itemName = "Frost Edge", quantity = 1 },
            },
        },
        Bob = {
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 1 },
            },
        },
    }
    h:load("!KRT/Services/Reserves.lua")

    local function findDisplayRow(list, itemId)
        for i = 1, #(list or {}) do
            if list[i] and list[i].itemId == itemId then
                return list[i]
            end
        end
        return nil
    end

    local Service = h.addon.Services.Reserves
    Service:Load()

    local firstList = Service:GetDisplayList()
    local firstColdsteel = findDisplayRow(firstList, 1201)
    local firstFrost = findDisplayRow(firstList, 1301)

    assertTrue(firstColdsteel ~= nil, "expected initial Coldsteel row")
    assertTrue(firstFrost ~= nil, "expected initial Frost row")
    local firstColdsteelPlayers = firstColdsteel.players

    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 2 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 1 },
            },
        },
    }
    Service:Load()

    local secondList = Service:GetDisplayList()
    local secondColdsteel = findDisplayRow(secondList, 1201)
    local secondFrost = findDisplayRow(secondList, 1301)

    assertTrue(secondList == firstList, "expected display list table to be reused")
    assertTrue(secondColdsteel == firstColdsteel, "expected rebuild to reuse the same item row table")
    assertTrue(secondColdsteel.players == firstColdsteelPlayers, "expected reused row to keep its player row buffer")

    local seen = {}
    for i = 1, #(secondColdsteel.players or {}) do
        local player = secondColdsteel.players[i]
        seen[player.name] = player
    end
    assertTrue(seen.Alice ~= nil, "expected reused row to keep active reserve player row")
    assertTrue(seen.Cara ~= nil, "expected reused row to add new reserve player row")
    assertTrue(seen.Bob == nil, "expected reused row to clear stale reserve player row")
    assertTrue(secondFrost == nil, "expected removed item row to be cleared from display list")
    assertEqual(#secondList, 1, "expected display list tail rows to be cleared")
end)

test("reserves format supports filtering to current raid players", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Bob = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1201 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name, raidNum)
            local rid = tonumber(raidNum) or 0
            if rid == 1 and (name == "Alice" or name == "Cara") then
                return 100
            end
            if rid == 2 and name == "Bob" then
                return 200
            end
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    local Service = Reserves
    Service:Load()

    local allPlayers = Service:FormatReservedPlayersLine(1201, false, false, false)
    local currentRaidOnly = Service:FormatReservedPlayersLine(1201, false, false, false, true)
    local raidTwoOnly = Service:FormatReservedPlayersLine(1201, false, false, false, true, 2)
    local raidTwoViaModule = Reserves:FormatReservedPlayersLine(1201, false, false, false, true, 2)
    local hasCurrentRaidPlayer = Service:HasCurrentRaidPlayersForItem(1201)
    local hasRaidTwoPlayer = Service:HasCurrentRaidPlayersForItem(1201, 2)
    local hasUnknownRaidPlayer = Service:HasCurrentRaidPlayersForItem(1201, 999)
    local hasRaidTwoPlayerViaModule = Reserves:HasCurrentRaidPlayersForItem(1201, 2)

    assertEqual(allPlayers, "Alice, Bob, Cara", "expected default formatting to keep all reserved players")
    assertEqual(currentRaidOnly, "Alice, Cara", "expected current-raid filtering to keep only active raid players")
    assertEqual(raidTwoOnly, "Bob", "expected explicit raid filter to target the provided raid id")
    assertEqual(raidTwoViaModule, "Bob", "expected module wrapper to pass filtering args to the service")
    assertTrue(hasCurrentRaidPlayer == true, "expected current raid to report at least one eligible reserve player")
    assertTrue(hasRaidTwoPlayer == true, "expected explicit raid id with roster matches to report eligible reserve players")
    assertTrue(hasUnknownRaidPlayer ~= true, "expected explicit raid id without matches to report no eligible reserve players")
    assertTrue(hasRaidTwoPlayerViaModule == true, "expected module wrapper to forward HasCurrentRaidPlayersForItem args")
end)

test("reserves expose item and roster match context for master loot", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1201, plus = 4 },
            },
        },
        Bob = {
            reserves = {
                { rawID = 1201, plus = 2 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1301 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "srImportMode", 1, { srImportMode = 0 })
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name, raidNum)
            local rid = tonumber(raidNum) or 0
            if rid == 1 and name == "Alice" then
                return 100
            end
            if rid == 2 and name == "Bob" then
                return 200
            end
            return 0
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local itemContext = Reserves:GetItemReserveContext(1201)
    assertTrue(itemContext.hasReserves == true, "expected item context to report reserve data")
    assertTrue(itemContext.hasPresentReserve == true, "expected item context to report a current-raid reserve")
    assertEqual(itemContext.mode, "plus", "expected item context to expose import mode")
    assertEqual(itemContext.totalReserveCount, 2, "expected item context to count all reservers")
    assertEqual(itemContext.presentReserveCount, 1, "expected item context to count current-raid reservers")
    assertEqual(itemContext.missingReserveCount, 1, "expected item context to count reserve names outside current raid")
    assertEqual(itemContext.presentPlayersText, "Alice (P+4)", "expected present reserve text to keep plus data")
    assertEqual(itemContext.missingPlayersText, "Bob (P+2)", "expected missing reserve text to keep plus data")

    local report = Reserves:GetReadinessReport().rosterReport
    assertEqual(report.totalReservePlayers, 3, "expected report to count unique imported reserve players")
    assertEqual(report.presentReservePlayers, 1, "expected report to count reserve players in current raid")
    assertEqual(report.missingReservePlayers, 2, "expected report to count reserve players outside current raid")
    assertEqual(report.presentPlayersText, "Alice", "expected report to list current-raid reserve players")
    assertEqual(report.missingPlayersText, "Bob, Cara", "expected report to list imported names missing from current raid")
end)

test("reserves name match report suggests read-only softres roster name fixes", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alicee = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Bbo = {
            reserves = {
                { rawID = 1202 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1203 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name, raidNum)
            local rid = tonumber(raidNum) or 0
            if rid == 1 and (name == "Alice" or name == "Bob" or name == "Dan") then
                return 100
            end
            return 0
        end,
        GetPlayers = function(_, raidNum)
            if tonumber(raidNum) ~= 1 then
                return {}
            end
            return {
                { name = "Alice" },
                { name = "Bob" },
                { name = "Dan" },
            }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local report = Reserves:GetReadinessReport().nameMatchReport

    assertEqual(report.reservePlayersOutsideRaidText, "Alicee, Bbo, Cara", "expected all misspelled reserve names to be reported outside raid")
    assertEqual(report.raidPlayersWithoutReserveText, "Alice, Bob, Dan", "expected all unmatched raid names to be reported without exact reserves")
    assertEqual(#report.strongMatches, 1, "expected one strong name suggestion")
    assertEqual(report.strongMatches[1].reserveName, "Alicee", "expected Alicee to be the strong reserve-side match")
    assertEqual(report.strongMatches[1].raidName, "Alice", "expected Alice to be the strong raid-side match")
    assertEqual(#report.weakMatches, 1, "expected one weak name suggestion")
    assertEqual(report.weakMatches[1].reserveName, "Bbo", "expected Bbo to be the weak reserve-side match")
    assertEqual(report.weakMatches[1].raidName, "Bob", "expected Bob to be the weak raid-side match")
    assertEqual(report.unmatchedReservePlayersText, "Cara", "expected Cara to remain unmatched")
    assertEqual(report.unmatchedRaidPlayersText, "Dan", "expected Dan to remain unmatched")
    assertTrue(_G.KRT_Reserves.Alicee ~= nil, "expected name report to avoid mutating imported reserves")
    assertTrue(_G.KRT_Reserves.Alice == nil, "expected name report to avoid writing corrected reserve names")
end)

test("reserves manual aliases resolve SoftRes eligibility without mutating imported names", function()
    local h = newHarness()
    _G.KRT_Options = {
        Reserves = {
            srImportMode = 1,
            nameAliases = {
                alicee = "Alice",
            },
        },
    }
    _G.KRT_Reserves = {
        Alicee = {
            playerNameDisplay = "Alicee",
            reserves = {
                { rawID = 1201, quantity = 1, plus = 3 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name)
            return name == "Alice" and 100 or 0
        end,
        GetPlayers = function()
            return { { name = "Alice" } }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()

    local Reserves = h.addon.Services.Reserves
    assertEqual(Reserves:GetReserveCountForItem(1201, "Alice"), 1, "expected alias to feed SR count")
    assertEqual(Reserves:GetPlusForItem(1201, "Alice"), 3, "expected alias to feed plus value")
    assertTrue(Reserves:HasCurrentRaidPlayersForItem(1201, 1) == true, "expected alias to match a present raid player")
    assertTrue(_G.KRT_Reserves.Alicee ~= nil, "expected source reserve key to remain unchanged")
    assertTrue(_G.KRT_Reserves.Alice == nil, "expected alias to avoid mutating imported reserve names")
end)

test("reserves alias readiness report reports applied aliases separately from suggestions", function()
    local h = newHarness()
    _G.KRT_Options = {
        Reserves = {
            nameAliases = {
                alicee = "Alice",
            },
        },
    }
    _G.KRT_Reserves = {
        Alicee = { playerNameDisplay = "Alicee", reserves = { { rawID = 1201 } } },
        Bbo = { playerNameDisplay = "Bbo", reserves = { { rawID = 1202 } } },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name)
            return (name == "Alice" or name == "Bob") and 100 or 0
        end,
        GetPlayers = function()
            return { { name = "Alice" }, { name = "Bob" } }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()

    local report = h.addon.Services.Reserves:GetReadinessReport()

    assertEqual(report.nameMatchReport.aliasMatchesText, "Alicee -> Alice", "expected applied alias text")
    assertEqual(report.nameMatchReport.weakMatches[1].reserveName, "Bbo", "expected unmatched typo to stay suggested")
    assertEqual(report.nameMatchReport.weakMatches[1].raidName, "Bob", "expected remaining suggestion")
    assertEqual(report.rosterReport.presentReservePlayers, 1, "expected alias to count as present reserve")
end)

test("reserves readiness report consolidates item roster and name-match context", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alicee = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Bob = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1203 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name, raidNum)
            local rid = tonumber(raidNum) or 0
            if rid == 1 and name == "Bob" then
                return 100
            end
            return 0
        end,
        GetPlayers = function(_, raidNum)
            if tonumber(raidNum) ~= 1 then
                return {}
            end
            return {
                { name = "Alice" },
                { name = "Bob" },
                { name = "Dan" },
            }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local report = Reserves:GetReadinessReport(1201)

    assertTrue(report ~= nil, "expected readiness report to be returned")
    assertEqual(report.itemId, 1201, "expected readiness report to keep the current item id")
    assertTrue(report.hasReserveData == true, "expected readiness report to detect imported SoftRes data")
    assertTrue(report.hasItemReserves == true, "expected readiness report to detect current-item reserves")
    assertTrue(report.hasEligibleItemReserve == true, "expected readiness report to detect an in-raid item reserver")
    assertEqual(report.itemContext.totalReserveCount, 2, "expected readiness item context to count current-item reservers")
    assertEqual(report.rosterReport.totalReservePlayers, 3, "expected readiness roster report to count imported players")
    assertEqual(report.rosterReport.presentReservePlayers, 1, "expected readiness roster report to count exact in-raid SoftRes names")
    assertEqual(report.nameMatchReport.strongMatches[1].reserveName, "Alicee", "expected readiness name report to include strong suggestions")
    assertEqual(report.nameMatchReport.strongMatches[1].raidName, "Alice", "expected readiness name report to include the raid-side suggestion")
    assertEqual(report.nameMatchReport.unmatchedReservePlayersText, "Cara", "expected readiness report to preserve unmatched reserve names")
    assertEqual(report.summaryToken, "1201|1|1|2|3|1|2|1|0|Cara", "expected readiness token to summarize UI-relevant report changes")
    assertTrue(_G.KRT_Reserves.Alicee ~= nil, "expected readiness report to avoid mutating imported reserves")
    assertTrue(_G.KRT_Reserves.Alice == nil, "expected readiness report to avoid writing corrected reserve names")
end)

test("reserves readiness report exposes read-only health audit signals", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alicee = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Bob = {
            reserves = {
                { rawID = 1201 },
            },
        },
        Cara = {
            reserves = {
                { rawID = 1203 },
            },
        },
    }
    h.addon.Services.Raid = {
        GetPlayerID = function(_, name, raidNum)
            local rid = tonumber(raidNum) or 0
            if rid == 1 and name == "Bob" then
                return 100
            end
            return 0
        end,
        GetPlayers = function(_, raidNum)
            if tonumber(raidNum) ~= 1 then
                return {}
            end
            return {
                { name = "Alice" },
                { name = "Bob" },
                { name = "Dan" },
            }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local report = Reserves:GetReadinessReport(1201)
    local health = report.health

    assertTrue(type(health) == "table", "expected readiness report to expose health audit data")
    assertEqual(health.severity, "warning", "expected mixed roster/import issues to produce warning severity")
    assertEqual(health.issueCount, 4, "expected health audit to count issue categories")
    assertEqual(health.importedPlayersOutsideRaidCount, 2, "expected health audit to count imported names outside raid")
    assertEqual(health.raidPlayersWithoutReserveCount, 2, "expected health audit to count raid players without exact SoftRes")
    assertEqual(health.suggestedNameMatchCount, 1, "expected health audit to count suggested name matches")
    assertEqual(health.unmatchedReserveCount, 1, "expected health audit to count unmatched imported names after suggestions")
    assertEqual(health.unmatchedRaidCount, 1, "expected health audit to count unmatched raid names after suggestions")
    assertTrue(health.hasCurrentItemIssue ~= true, "expected current item with eligible reservers to avoid item issue")
    assertTrue(_G.KRT_Reserves.Alicee ~= nil, "expected health audit to avoid mutating imported reserves")
    assertTrue(_G.KRT_Reserves.Alice == nil, "expected health audit to avoid writing corrected reserve names")
end)

test("reserves readiness report marks no-data health as error", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h.addon.Services.Raid = {
        GetPlayerID = function()
            return 0
        end,
        GetPlayers = function()
            return {
                { name = "Alice" },
            }
        end,
    }
    h.feature.Services = h.addon.Services
    h.Database.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local report = Reserves:GetReadinessReport(1201)
    local health = report.health

    assertEqual(health.severity, "error", "expected missing SoftRes data to produce error severity")
    assertEqual(health.issueCount, 1, "expected no-data health to report one issue category")
    assertTrue(health.hasNoData == true, "expected no-data health flag")
    assertTrue(health.hasCurrentItemIssue ~= true, "expected no-data health to avoid duplicate current-item issue")
end)

test("slash help supports focused command pages", function()
    local h = newHarness()
    _G.SlashCmdList = {}
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("help logger")

    assertContains(h.logs.info, "Commands: valid subcommands for |caaf49141/krt logger|r:", "expected focused logger help header")
end)

test("slash reserves alias commands persist aliases and print list", function()
    local h = newHarness()
    _G.SlashCmdList = {}
    _G.KRT_Options = {}
    _G.KRT_Reserves = {}

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Services/Reserves/Import.lua")
    h:load("!KRT/Services/Reserves/Aliases.lua")
    h:load("!KRT/Services/Reserves/Display.lua")
    h:load("!KRT/Services/Reserves.lua")
    h.addon.Services.Reserves:Load()
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    SlashCmdList.KRT("sr alias Alicee Alice")
    assertEqual(_G.KRT_Options.Reserves.nameAliases.alicee, "Alice", "expected alias to persist")
    assertContains(h.logs.info, "SoftRes alias set: Alicee -> Alice.", "expected set message")

    SlashCmdList.KRT("sr aliases")
    assertContains(h.logs.info, "alicee -> Alice", "expected alias list entry")

    SlashCmdList.KRT("sr unalias Alicee")
    assertTrue(_G.KRT_Options.Reserves.nameAliases.alicee == nil, "expected alias to be cleared")
end)

test("slash reserves list and import bypass master loot access gate", function()
    local h = newHarness()
    local gateCalls = 0
    local uiCalls = {}
    _G.SlashCmdList = {}

    h.addon.Services.Raid = {
        EnsureMasterOnlyAccess = function()
            gateCalls = gateCalls + 1
            return false
        end,
    }
    h.feature.Services = h.addon.Services
    h.addon.UI.Widgets.IsEnabled = function()
        return true
    end
    h.addon.UI.Widgets.IsRegistered = function(widgetId)
        return widgetId == "Reserves"
    end
    h.addon.UI.Widgets.Call = function(widgetId, methodName)
        uiCalls[#uiCalls + 1] = {
            widgetId = widgetId,
            methodName = methodName,
        }
        return true
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    SlashCmdList.KRT("res")
    SlashCmdList.KRT("sr import")

    assertEqual(gateCalls, 0, "expected reserve commands to stay available outside Master Loot")
    assertEqual(#uiCalls, 2, "expected reserve list and import widget calls")
    assertEqual(uiCalls[1].widgetId, "Reserves", "expected reserve list widget id")
    assertEqual(uiCalls[1].methodName, "Toggle", "expected reserve list toggle call")
    assertEqual(uiCalls[2].widgetId, "Reserves", "expected reserve import widget id")
    assertEqual(uiCalls[2].methodName, "ToggleImport", "expected reserve import call")
end)

test("slash reserves check prints current item softres readiness", function()
    local h = newHarness()
    local link = h.registerItem(1201, "Readiness Blade")
    _G.SlashCmdList = {}

    h.addon.Services.Raid = {
        EnsureMasterOnlyAccess = function()
            return true
        end,
    }
    h.addon.Services.Loot = {
        GetItemLink = function()
            return link
        end,
    }
    h.addon.Services.Reserves = {
        GetReadinessReport = function(_, itemId)
            assertEqual(itemId, 1201, "expected slash readiness check to pass the current item id")
            return {
                itemId = 1201,
                hasReserveData = true,
                hasItemReserves = true,
                hasEligibleItemReserve = true,
                itemContext = {
                    totalReserveCount = 2,
                    presentReserveCount = 1,
                    missingReserveCount = 1,
                    presentPlayersText = "Alice",
                    missingPlayersText = "Bob",
                },
                rosterReport = {
                    totalReservePlayers = 3,
                    presentReservePlayers = 1,
                    missingReservePlayers = 2,
                    presentPlayersText = "Alice",
                    missingPlayersText = "Bob, Cara",
                },
                nameMatchReport = {
                    strongMatches = {
                        { reserveName = "Alicee", raidName = "Alice" },
                    },
                    weakMatches = {},
                    unmatchedReservePlayersText = "Cara",
                    unmatchedRaidPlayersText = "Dan",
                },
                health = {
                    severity = "warning",
                    issueCount = 4,
                    importedPlayersOutsideRaidCount = 2,
                    raidPlayersWithoutReserveCount = 2,
                    suggestedNameMatchCount = 1,
                    unmatchedReserveCount = 1,
                    unmatchedRaidCount = 1,
                    hasCurrentItemIssue = false,
                },
            }
        end,
    }
    h.feature.Services = h.addon.Services

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("res check")

    assertContains(h.logs.info, "SoftRes readiness:", "expected readiness report title")
    assertContains(h.logs.info, "Current item: " .. link, "expected current item link in readiness report")
    assertContains(h.logs.info, "Current item SoftRes: 1/2 players in raid.", "expected current item reserve summary")
    assertContains(h.logs.info, "Item in raid: Alice", "expected current item present players")
    assertContains(h.logs.info, "Item outside raid: Bob", "expected current item missing players")
    assertContains(h.logs.info, "Imported SoftRes: 3 players, 1 in raid, 2 outside raid.", "expected roster summary")
    assertContains(h.logs.info, "Health: Warning", "expected health severity in readiness report")
    assertContains(h.logs.info, "Issues: 4", "expected health issue count in readiness report")
    assertContains(h.logs.info, "Imported names outside raid: 2", "expected imported-outside-raid health signal")
    assertContains(h.logs.info, "Raid players without exact SoftRes: 2", "expected raid-without-softres health signal")
    assertContains(h.logs.info, "Suggested name matches: 1", "expected name-match health signal")
    assertContains(h.logs.info, "Possible name matches: Alicee -> Alice", "expected name-match suggestions")
    assertContains(h.logs.info, "Unmatched SoftRes names: Cara", "expected unmatched reserve names")
    assertContains(h.logs.info, "Raid players without exact SoftRes: Dan", "expected unmatched raid names")
end)

test("slash softres check prints roster readiness without current item", function()
    local h = newHarness()
    _G.SlashCmdList = {}

    h.addon.Services.Raid = {
        EnsureMasterOnlyAccess = function()
            return true
        end,
    }
    h.addon.Services.Loot = {
        GetItemLink = function()
            return nil
        end,
    }
    h.addon.Services.Reserves = {
        GetReadinessReport = function(_, itemId)
            assertEqual(itemId, nil, "expected slash readiness check to omit item id without current item")
            return {
                hasReserveData = true,
                hasItemReserves = false,
                hasEligibleItemReserve = false,
                itemContext = {
                    totalReserveCount = 0,
                    presentReserveCount = 0,
                    missingReserveCount = 0,
                },
                rosterReport = {
                    totalReservePlayers = 2,
                    presentReservePlayers = 2,
                    missingReservePlayers = 0,
                    presentPlayersText = "Alice, Bob",
                    missingPlayersText = "",
                },
                nameMatchReport = {
                    strongMatches = {},
                    weakMatches = {},
                    unmatchedReservePlayersText = "",
                    unmatchedRaidPlayersText = "Cara",
                },
                health = {
                    severity = "warning",
                    issueCount = 1,
                    importedPlayersOutsideRaidCount = 0,
                    raidPlayersWithoutReserveCount = 1,
                    suggestedNameMatchCount = 0,
                    unmatchedReserveCount = 0,
                    unmatchedRaidCount = 1,
                    hasCurrentItemIssue = false,
                },
            }
        end,
    }
    h.feature.Services = h.addon.Services

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("sr check")

    assertContains(h.logs.info, "SoftRes readiness:", "expected readiness report title")
    assertContains(h.logs.info, "Current item: None", "expected no-current-item line")
    assertContains(h.logs.info, "Imported SoftRes: 2 players, 2 in raid, 0 outside raid.", "expected roster summary")
    assertContains(h.logs.info, "Health: Warning", "expected health severity for raid players without exact reserves")
    assertContains(h.logs.info, "Issues: 1", "expected health issue count for raid players without exact reserves")
    assertContains(h.logs.info, "In raid: Alice, Bob", "expected in-raid reserve players")
    assertContains(h.logs.info, "Raid players without exact SoftRes: Cara", "expected raid players without exact reserves")
end)

test("slash perf toggles runtime performance logging", function()
    local h = newHarness()
    _G.SlashCmdList = {}

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("perf on")

    assertTrue(h.addon.State.perfEnabled == true, "expected /krt perf on to enable runtime performance logging")
    assertContains(h.logs.info, "Performance logging: enabled", "expected perf command to report enabled state")

    _G.SlashCmdList.KRT("perf threshold 12")

    assertEqual(h.addon.State.perfThresholdMs, 12, "expected /krt perf threshold to update the runtime threshold")
    assertContains(h.logs.info, "Performance logging threshold: 12ms.", "expected perf threshold command to report the new threshold")

    _G.SlashCmdList.KRT("perf off")

    assertTrue(h.addon.State.perfEnabled ~= true, "expected /krt perf off to disable runtime performance logging")
    assertContains(h.logs.info, "Performance logging: disabled.", "expected perf command to report disabled state")
end)

test("slash perf reports and resets runtime performance aggregates", function()
    local h = newHarness()
    local rows = {
        { label = "slow block", count = 2, totalMs = 12, avgMs = 6, maxMs = 8 },
        { label = "fast block", count = 1, totalMs = 4, avgMs = 4, maxMs = 4 },
    }
    local resetCalled = false
    _G.SlashCmdList = {}

    function h.addon:_PerfGetStats()
        local out = {}
        for i = 1, #rows do
            out[i] = rows[i]
        end
        return out
    end

    function h.addon:_PerfResetStats()
        resetCalled = true
        rows = {}
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("perf report")

    assertContains(h.logs.info, "Performance report: 2 block(s).", "expected perf report title")
    assertContains(h.logs.info, "1) slow block count=2 total=12ms avg=6ms max=8ms", "expected slow block perf row")
    assertContains(h.logs.info, "2) fast block count=1 total=4ms avg=4ms max=4ms", "expected fast block perf row")

    _G.SlashCmdList.KRT("perf reset")

    assertTrue(resetCalled, "expected perf reset command to clear runtime perf stats")
    assertContains(h.logs.info, "Performance report reset.", "expected perf reset acknowledgement")

    _G.SlashCmdList.KRT("perf report")

    assertContains(h.logs.info, "Performance report: no measured blocks.", "expected empty perf report after reset")
end)

test("slash perf audit reports actionable runtime sync and item summaries", function()
    local h = newHarness()
    _G.SlashCmdList = {}

    function h.addon:_PerfGetStats()
        return {
            { label = "Logger.View.FillLootList", count = 4, totalMs = 40, avgMs = 10, maxMs = 20 },
            { label = "Reserves.GetDisplayList", count = 2, totalMs = 6, avgMs = 3, maxMs = 4 },
        }
    end

    h.Database.GetSyncer = function()
        return {
            GetSyncMetrics = function()
                return {
                    outgoingMessages = 3,
                    outgoingChunks = 2,
                    outgoingBytes = 600,
                    outgoingRequests = 1,
                    outgoingSnapshots = 1,
                    incomingMessages = 2,
                    incomingChunks = 1,
                    incomingBytes = 200,
                    incomingRequests = 1,
                    incomingSnapshots = 0,
                }
            end,
        }
    end

    h.addon.Item.GetInfoMetrics = function()
        return {
            totalRequests = 5,
            requestsJoined = 2,
            pendingRequests = 1,
            getItemInfoCalls = 6,
            tooltipProbes = 3,
        }
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("perf audit")

    assertContains(h.logs.info, "Performance audit: runtime blocks=2 total=46ms top=Logger.View.FillLootList total=40ms max=20ms.", "expected runtime perf audit summary")
    assertContains(h.logs.info, "Performance audit sync: out bytes=600 chunks=2 avg=300B/chunk; in bytes=200 chunks=1 avg=200B/chunk.", "expected sync perf audit summary")
    assertContains(h.logs.info, "Performance audit items: requests=5 joined=2 pending=1 GetItemInfo=6 tooltip=3.", "expected item perf audit summary")
end)

test("slash perf reports and resets sync payload metrics", function()
    local h = newHarness()
    local resetCalled = false
    _G.SlashCmdList = {}

    h.Database.GetSyncer = function()
        return {
            GetSyncMetrics = function()
                return {
                    outgoingMessages = 3,
                    outgoingChunks = 2,
                    outgoingBytes = 360,
                    outgoingRequests = 1,
                    outgoingSnapshots = 1,
                    incomingMessages = 4,
                    incomingChunks = 3,
                    incomingBytes = 540,
                    incomingRequests = 1,
                    incomingSnapshots = 1,
                    modes = {
                        {
                            mode = "PUSH",
                            outgoingMessages = 2,
                            outgoingChunks = 2,
                            outgoingBytes = 360,
                            outgoingRequests = 0,
                            outgoingSnapshots = 1,
                            incomingMessages = 3,
                            incomingChunks = 3,
                            incomingBytes = 540,
                            incomingRequests = 0,
                            incomingSnapshots = 1,
                        },
                        {
                            mode = "SYNC",
                            outgoingMessages = 1,
                            outgoingChunks = 0,
                            outgoingBytes = 0,
                            outgoingRequests = 1,
                            outgoingSnapshots = 0,
                            incomingMessages = 1,
                            incomingChunks = 0,
                            incomingBytes = 0,
                            incomingRequests = 1,
                            incomingSnapshots = 0,
                        },
                    },
                }
            end,
            ResetSyncMetrics = function()
                resetCalled = true
            end,
        }
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("perf sync")

    assertContains(
        h.logs.info,
        "Sync performance report: out messages=3 chunks=2 bytes=360 requests=1 snapshots=1; in messages=4 chunks=3 bytes=540 requests=1 snapshots=1.",
        "expected sync perf summary"
    )
    assertContains(
        h.logs.info,
        "PUSH out messages=2 chunks=2 bytes=360 requests=0 snapshots=1; in messages=3 chunks=3 bytes=540 requests=0 snapshots=1.",
        "expected PUSH sync perf row"
    )
    assertContains(
        h.logs.info,
        "SYNC out messages=1 chunks=0 bytes=0 requests=1 snapshots=0; in messages=1 chunks=0 bytes=0 requests=1 snapshots=0.",
        "expected SYNC sync perf row"
    )

    _G.SlashCmdList.KRT("perf reset")

    assertTrue(resetCalled, "expected perf reset to clear sync payload metrics")
end)

test("slash perf reports and resets item request metrics", function()
    local h = newHarness()
    _G.SlashCmdList = {}
    _G.GetItemInfo = function()
        return nil
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Item.lua")
    h.feature.Item = h.addon.Item
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    local handle = h.addon.Item.RequestItemInfo(32001, function() end)
    handle:Cancel()
    h:flushTimers()

    _G.SlashCmdList.KRT("perf items")

    assertContains(
        h.logs.info,
        "Item performance report: requests=1 started=1 joined=0 immediate=0 pending=0 callbacks=0 completed=0 timeouts=0 cancelled=1 GetItemInfo=2 tooltip=1.",
        "expected item perf summary"
    )

    _G.SlashCmdList.KRT("perf reset")
    _G.SlashCmdList.KRT("perf items")

    assertContains(
        h.logs.info,
        "Item performance report: requests=0 started=0 joined=0 immediate=0 pending=0 callbacks=0 completed=0 timeouts=0 cancelled=0 GetItemInfo=0 tooltip=0.",
        "expected item perf metrics to reset"
    )
end)

test("slash bug prints local diagnostic summary", function()
    local h = newHarness()
    _G.SlashCmdList = {}
    _G.KRT_Raids = { { raidNid = 10 }, { raidNid = 11 } }
    _G.KRT_Reserves = {
        Alice = { reserves = { { rawID = 1001 } } },
        Bob = { reserves = { { rawID = 1002 }, { rawID = 1003 } } },
    }
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end
    h.Database.GetRaidSchemaVersion = function()
        return 5
    end
    h.Database.GetRaidStoreOrNil = function()
        return {
            GetAllRaids = function()
                return _G.KRT_Raids
            end,
            GetRaidNidByIndex = function(_, index)
                local raid = _G.KRT_Raids and _G.KRT_Raids[index]
                return raid and raid.raidNid or nil
            end,
        }
    end
    h.addon.GetLogLevel = function()
        return 3
    end
    h.addon.logLevels = { INFO = 3 }
    h.addon.Services.Raid.IsMasterLooter = function()
        return true
    end
    h.addon.Services.Raid.GetPlayerRoleState = function()
        return {
            inRaid = true,
            rank = 2,
            isLeader = true,
            isAssistant = false,
            hasRaidLeadership = true,
            isMasterLooter = true,
        }
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")
    h:load("!KRT/Services/Reserves.lua")

    _G.SlashCmdList.KRT("bug")

    assertContains(h.logs.info, "KRT bug report:", "expected bug report title")
    assertContains(h.logs.info, "Addon: 9.8.7", "expected addon version in bug report")
    assertContains(h.logs.info, "Interface: 30300", "expected interface in bug report")
    assertContains(h.logs.info, "Raid schema: 5", "expected schema in bug report")
    assertContains(h.logs.info, "Raid history: 2", "expected raid history count in bug report")
    assertContains(h.logs.info, "Reserves: players=2 entries=3", "expected reserves summary in bug report")
    assertContains(h.logs.info, "Role: inRaid=yes leader=yes assistant=no masterLooter=yes", "expected role summary in bug report")
end)

test("slash version prints local addon compatibility summary", function()
    local h = newHarness()
    _G.SlashCmdList = {}
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end
    h.Database.GetRaidSchemaVersion = function()
        return 5
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/EntryPoints/SlashEvents.lua")

    _G.SlashCmdList.KRT("version")

    assertContains(h.logs.info, "KRT version:", "expected version command title")
    assertContains(h.logs.info, "Addon: 9.8.7", "expected addon version")
    assertContains(h.logs.info, "Interface: 30300", "expected interface version")
    assertContains(h.logs.info, "Raid schema: 5", "expected raid schema version")
end)

test("comms version check sends group request and records acknowledgements", function()
    local h = newHarness()
    local sent = {}
    _G.GetNumRaidMembers = function()
        return 10
    end
    _G.GetNumPartyMembers = function()
        return 0
    end
    _G.SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = target,
        }
    end
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end
    h.Database.GetRaidSchemaVersion = function()
        return 5
    end
    h.Database.GetSyncer = function()
        return {
            GetProtocolVersion = function()
                return 2
            end,
        }
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")

    local ok = h.addon.Comms:RequestVersionCheck()

    assertTrue(ok == true, "expected version request to be sent in raid")
    assertEqual(#sent, 1, "expected one group version request")
    assertEqual(sent[1].prefix, "KRTVersion", "expected dedicated version prefix")
    assertEqual(sent[1].channel, "RAID", "expected raid transport")
    assertTrue(sent[1].msg:match("^REQ|") ~= nil, "expected version request payload")

    local handled = h.addon.Comms:HandleVersionMessage("KRTVersion", "ACK|9.8.6|30300|5|2", "RAID", "Alice")

    assertTrue(handled == true, "expected version acknowledgement to be handled")
    assertContains(h.logs.info, "Version: Alice addon=9.8.6 interface=30300 schema=5 sync=2", "expected ack summary")
end)

test("comms version check replies to requests by whisper", function()
    local h = newHarness()
    local sent = {}
    _G.SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = target,
        }
    end
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end
    h.Database.GetRaidSchemaVersion = function()
        return 5
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")

    local handled = h.addon.Comms:HandleVersionMessage("KRTVersion", "REQ|9.8.5|30300|4|1", "RAID", "Bob")

    assertTrue(handled == true, "expected version request to be handled")
    assertEqual(#sent, 1, "expected one version acknowledgement")
    assertEqual(sent[1].prefix, "KRTVersion", "expected dedicated version prefix")
    assertEqual(sent[1].channel, "WHISPER", "expected direct reply")
    assertEqual(sent[1].target, "Bob", "expected requester target")
    assertTrue(sent[1].msg:match("^ACK|9%.8%.7|30300|5|") ~= nil, "expected local version payload")
end)

test("comms exposes shared version metadata", function()
    local h = newHarness()
    _G.GetAddOnMetadata = function(_, key)
        if key == "Version" then
            return "9.8.7"
        end
        if key == "Interface" then
            return "30300"
        end
        return nil
    end
    h.Database.GetRaidSchemaVersion = function()
        return 5
    end
    h.Database.GetSyncer = function()
        return {
            GetProtocolVersion = function()
                return 2
            end,
        }
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")

    local info = h.addon.Comms.GetVersionInfo()

    assertEqual(info.addonVersion, "9.8.7", "expected addon version from shared comms metadata")
    assertEqual(info.interfaceVersion, "30300", "expected interface version from shared comms metadata")
    assertEqual(info.raidSchemaVersion, "5", "expected raid schema from shared comms metadata")
    assertEqual(info.syncProtocolVersion, "2", "expected sync protocol from shared comms metadata")
end)

test("json decoder parses softres export primitives and arrays", function()
    local h = newHarness()
    h:load("!KRT/Modules/Json.lua")

    local parsed =
        h.addon.Json.GetDecoded('{"metadata":{"id":"ABC123","origin":"raidres"},"softreserves":[{"name":"Alice","items":[{"id":1201,"quality":4,"sr_plus":2}]}],"hardreserves":[]}')

    assertEqual(parsed.metadata.id, "ABC123", "expected object string field")
    assertEqual(parsed.metadata.origin, "raidres", "expected nested metadata field")
    assertEqual(parsed.softreserves[1].name, "Alice", "expected array object field")
    assertEqual(parsed.softreserves[1].items[1].id, 1201, "expected numeric item id")
    assertEqual(parsed.softreserves[1].items[1].sr_plus, 2, "expected plus value")
end)

test("json decoder rejects malformed softres payloads", function()
    local h = newHarness()
    h:load("!KRT/Modules/Json.lua")

    local parsed, reason = h.addon.Json.GetDecoded('{"softreserves":[')

    assertEqual(parsed, nil, "expected malformed JSON to fail")
    assertTrue(type(reason) == "string" and reason ~= "", "expected decoder failure reason")
end)

test("comms payload helpers encode split and pack addon-message fields", function()
    local h = newHarness()

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/Comms.lua")
    h:load("!KRT/Modules/Base64.lua")

    local payload = h.addon.Comms.Payload
    local encoded = payload.EncodeText("Alpha|Beta")
    local packed = payload.PackFields("|", "ROW", encoded, nil, "tail")
    local fields, n = payload.SplitFields(packed, "|")

    assertEqual(n, 4, "expected packed field count")
    assertEqual(fields[1], "ROW", "expected first payload field")
    assertEqual(payload.DecodeText(fields[2]), "Alpha|Beta", "expected encoded delimiter text to round-trip")
    assertEqual(fields[3], "", "expected nil payload fields to pack as empty strings")
    assertEqual(fields[4], "tail", "expected final payload field")
end)

test("runtime cleanup consumers use canonical public helper owners", function()
    local commsSource = readText("!KRT/Modules/Comms.lua")
    local distributionSource = readText("!KRT/Services/Loot/DistributionSession.lua")
    local listsSource = readText("!KRT/Modules/UI/ListController.lua")
    local loggerSource = readText("!KRT/Controllers/Logger.lua")
    local masterSource = readText("!KRT/Controllers/Master.lua")
    local warningsSource = readText("!KRT/Controllers/Warnings.lua")
    local raidStateSource = readText("!KRT/Services/Raid/State.lua")
    local reservesAliasesSource = readText("!KRT/Services/Reserves/Aliases.lua")
    local reservesImportSource = readText("!KRT/Services/Reserves/Import.lua")
    local reservesChatSource = readText("!KRT/Services/Reserves/Chat.lua")
    local dbSource = readText("!KRT/Database/DB.lua")
    local dbQueriesSource = readText("!KRT/Database/DBRaidQueries.lua")
    local dbStoreSource = readText("!KRT/Database/DBRaidStore.lua")
    local loggerViewSource = readText("!KRT/Services/Logger/View.lua")

    assertTextContains(commsSource, "function Payload.EncodeText", "Comms must expose public payload encode API")
    assertTextContains(commsSource, "function Payload.DecodeText", "Comms must expose public payload decode API")
    assertTextNotContains(distributionSource, "Comms._Payload", "Loot distribution must not consume private Comms payload helpers")

    assertTextContains(listsSource, "function Lists.MakeIndexedRowName", "UI.Lists must expose the indexed row-name factory")
    assertTextContains(loggerSource, 'UI.Lists.MakeIndexedRowName("RaidBtn")', "Logger raid lists should use shared row-name factory")
    assertTextContains(loggerSource, 'UI.Lists.MakeIndexedRowName("PlayerBtn")', "Logger player lists should use shared row-name factory")
    assertTextContains(loggerSource, 'UI.Lists.MakeIndexedRowName("ItemBtn")', "Logger loot lists should use shared row-name factory")
    assertTextContains(masterSource, 'UI.Lists.MakeIndexedRowName("PlayerBtn")', "Master roll list should use shared row-name factory")
    assertTextContains(warningsSource, 'Lists.MakeIndexedRowName("WarningBtn")', "Warnings list should use shared row-name factory")

    assertTextNotContains(raidStateSource, "local function trimText", "Raid state should consume Strings.TrimText directly")
    assertTextNotContains(reservesAliasesSource, "local function trimText", "Reserves aliases should consume Strings helpers directly")
    assertTextNotContains(reservesAliasesSource, "local function normalizeName", "Reserves aliases should consume Strings.NormalizeName directly")
    assertTextNotContains(reservesImportSource, "local function trimText", "Reserves import should consume Strings.TrimText directly")
    assertTextNotContains(reservesChatSource, "local function trimText", "Reserves chat should consume Strings.TrimText directly")
    assertTextNotContains(distributionSource, "local function normalizeText", "Loot distribution should consume Strings.NormalizeText directly")

    assertTextContains(dbSource, "function Database.IsBossFightRecord", "Database must expose the canonical boss-record predicate")
    assertEqual(countTextPattern(dbSource, "local function isBossFightRecord"), 1, "Database must own the only boss-record implementation")
    assertTextNotContains(dbQueriesSource, "local function isBossFightRecord", "DBRaidQueries must consume Database.IsBossFightRecord")
    assertTextNotContains(dbStoreSource, "local function isBossFightRecord", "DBRaidStore must consume Database.IsBossFightRecord")
    assertTextNotContains(loggerViewSource, "local function isBossFightRecord", "Logger View must consume Database.IsBossFightRecord")
end)

test("loot distribution session publishes item roll and done messages", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(9301, "Session Blade", 4, "Icon9301")
    local itemKey = h.addon.Item.GetItemStringFromLink(itemLink)

    h:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    h:load("!KRT/Modules/Comms.lua")
    h.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
        }
        return true
    end
    h:load("!KRT/Services/Loot/DistributionSession.lua")

    local Distribution = h.addon.Services.Loot._DistributionSession
    assertTrue(Distribution.PublishItem({
        itemKey = itemKey,
        itemLink = itemLink,
        itemName = "Session Blade",
        itemTexture = "Icon9301",
        quality = 4,
        count = 2,
        slot = 1,
    }) == true, "expected master looter to publish an item row")
    assertTrue(Distribution.PublishRollStart(itemKey, h.rollTypes.MAINSPEC, 30) == true, "expected roll start to publish")
    assertTrue(Distribution.PublishRollEnd(itemKey, "Alice", 98, "roll_resolution") == true, "expected roll end to publish")
    assertTrue(Distribution.PublishItemDone(itemKey, "Alice") == true, "expected item done to publish")

    local model = Distribution.GetDisplayModel()
    assertEqual(#sent, 4, "expected compact item roll and done messages")
    assertEqual(sent[1].prefix, "KRTDist", "expected dedicated distribution prefix")
    assertTrue(sent[1].msg:match("^ITEM|2|") ~= nil, "expected versioned item message")
    assertTrue(sent[2].msg:match("^ROLL_START|2|") ~= nil, "expected versioned roll-start message")
    assertTrue(sent[3].msg:match("^ROLL_END|2|") ~= nil, "expected versioned roll-end message")
    assertTrue(sent[4].msg:match("^ITEM_DONE|2|") ~= nil, "expected versioned item-done message")
    assertEqual(#model.rows, 1, "expected one distribution display row")
    assertEqual(model.rows[1].itemKey, itemKey, "expected item key to stay stable")
    assertEqual(model.rows[1].itemLink, itemLink, "expected item link to stay visible")
    assertEqual(model.rows[1].state, "done", "expected done state after award publication")
    assertEqual(model.rows[1].winnerName, "Alice", "expected final winner to be retained")
    assertEqual(model.rows[1].rollValue, 98, "expected final roll value to be retained")
    assertEqual(model.rows[1].rollType, h.rollTypes.MAINSPEC, "expected roll type to be retained")
end)

test("loot distribution session answers snapshot requests with versioned state", function()
    local source = newHarness()
    local target = newHarness()
    local sent = {}
    local itemLink = source.registerItem(9401, "Snapshot Blade", 4, "Icon9401")
    local itemKey = source.addon.Item.GetItemStringFromLink(itemLink)

    _G.SendAddonMessage = function(prefix, msg, channel, targetName)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = targetName,
        }
    end

    source:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    source:load("!KRT/Modules/Comms.lua")
    source.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = { prefix = prefix, msg = msg, channel = "RAID" }
        return true
    end
    source:load("!KRT/Services/Loot/DistributionSession.lua")

    local Distribution = source.addon.Services.Loot._DistributionSession
    Distribution.PublishItem({
        itemKey = itemKey,
        itemLink = itemLink,
        itemName = "Snapshot Blade",
        itemTexture = "Icon9401",
        quality = 4,
        count = 1,
        slot = 1,
    })
    Distribution.PublishRollStart(itemKey, source.rollTypes.RESERVED, 30)
    Distribution.PublishRollTick(itemKey, 19)

    sent = {}
    local handled = Distribution.HandleMessage("KRTDist", "SNAP_REQ|2|req-1", "WHISPER", "Raider")

    assertTrue(handled == true, "expected snapshot request to be handled")
    assertEqual(#sent, 1, "expected one snapshot reply")
    assertEqual(sent[1].prefix, "KRTDist", "expected distribution prefix")
    assertEqual(sent[1].channel, "WHISPER", "expected snapshot reply to whisper requester")
    assertEqual(sent[1].target, "Raider", "expected snapshot target")
    assertTrue(sent[1].msg:match("^SNAP|2|") ~= nil, "expected versioned snapshot payload")

    target:load("!KRT/Modules/Comms.lua")
    target:load("!KRT/Services/Loot/DistributionSession.lua")
    target.addon.Services.Loot._DistributionSession.HandleMessage(sent[1].prefix, sent[1].msg, sent[1].channel, "ML")

    local model = target.addon.Services.Loot._DistributionSession.GetDisplayModel()
    assertEqual(model.protocolVersion, 2, "expected protocol version in display model")
    assertEqual(#model.rows, 1, "expected snapshot to restore one row")
    assertEqual(model.rows[1].itemKey, itemKey, "expected snapshot item key")
    assertEqual(model.rows[1].state, "rolling", "expected rolling state")
    assertEqual(model.rows[1].remaining, 19, "expected tick state to survive snapshot")
end)

test("loot distribution session publishes tie and awarded state with versioned messages", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(9402, "Tie Blade", 4, "Icon9402")
    local itemKey = h.addon.Item.GetItemStringFromLink(itemLink)

    h:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    h:load("!KRT/Modules/Comms.lua")
    h.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = { prefix = prefix, msg = msg }
        return true
    end
    h:load("!KRT/Services/Loot/DistributionSession.lua")

    local Distribution = h.addon.Services.Loot._DistributionSession
    assertTrue(Distribution.PublishItem({ itemKey = itemKey, itemLink = itemLink, slot = 1 }) == true, "expected versioned item")
    assertTrue(Distribution.PublishTieStart(itemKey, { "Alice", "Bob" }) == true, "expected tie state")
    assertTrue(Distribution.PublishAwarded(itemKey, "Alice", 98) == true, "expected awarded state")

    local model = Distribution.GetDisplayModel()
    assertEqual(model.rows[1].state, "awarded", "expected awarded state")
    assertEqual(model.rows[1].winnerName, "Alice", "expected awarded winner")
    assertEqual(model.rows[1].rollValue, 98, "expected awarded roll")
    assertEqual(model.rows[1].tieNamesText, "Alice,Bob", "expected tie names to be retained")
    assertTrue(sent[1].msg:match("^ITEM|2|") ~= nil, "expected versioned item message to remain first")
    assertTrue(sent[2].msg:match("^TIE_START|2|") ~= nil, "expected versioned tie message")
    assertTrue(sent[3].msg:match("^AWARDED|2|") ~= nil, "expected versioned awarded message")
end)

test("loot service consumes distribution addon messages into a raider display model", function()
    local source = newHarness()
    local target = newHarness()
    local sent = {}
    local changed = 0
    local itemLink = source.registerItem(9302, "Synced Session Blade", 4, "Icon9302")
    local itemKey = source.addon.Item.GetItemStringFromLink(itemLink)

    source:setRaidRoleState({ inRaid = true, isMasterLooter = true })
    source:load("!KRT/Modules/Comms.lua")
    source.addon.Comms.Sync = function(prefix, msg)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
        }
        return true
    end
    source:load("!KRT/Services/Loot/DistributionSession.lua")

    source.addon.Services.Loot._DistributionSession.PublishItem({
        itemKey = itemKey,
        itemLink = itemLink,
        itemName = "Synced Session Blade",
        itemTexture = "Icon9302",
        quality = 4,
        count = 1,
        slot = 1,
    })
    source.addon.Services.Loot._DistributionSession.PublishRollStart(itemKey, source.rollTypes.RESERVED, 45)
    source.addon.Services.Loot._DistributionSession.PublishRollEnd(itemKey, "Bob", 87, "manual_resolution")
    source.addon.Services.Loot._DistributionSession.PublishItemDone(itemKey, "Bob")

    target.Bus.RegisterCallback(target.addon.Events.Internal.LootDistributionSessionChanged, function()
        changed = changed + 1
    end)
    target:setRaidRoleState({ inRaid = true, isMasterLooter = false })
    target:load("!KRT/Modules/Comms.lua")
    target:load("!KRT/Services/Loot.lua")

    for i = 1, #sent do
        local handled = target.addon.Services.Loot:HandleDistributionMessage(sent[i].prefix, sent[i].msg, "RAID", "ML")
        assertTrue(handled == true, "expected distribution message to be consumed")
    end

    local model = target.addon.Services.Loot:GetDistributionSessionModel()
    assertTrue(changed >= 4, "expected distribution bus event for incoming state changes")
    assertEqual(#model.rows, 1, "expected synced distribution model to contain one item")
    assertEqual(model.rows[1].itemKey, itemKey, "expected synced item key")
    assertEqual(model.rows[1].itemLink, itemLink, "expected synced item link")
    assertEqual(model.rows[1].state, "done", "expected synced done state")
    assertEqual(model.rows[1].winnerName, "Bob", "expected synced winner")
    assertEqual(model.rows[1].rollValue, 87, "expected synced roll value")
    assertEqual(model.rows[1].rollType, target.rollTypes.RESERVED, "expected synced roll type")
end)

test("loot service keeps booting when the distribution helper file is missing", function()
    local h = newHarness()

    h:load("!KRT/Services/Loot/Context.lua")
    h:load("!KRT/Services/Loot/State.lua")
    h:load("!KRT/Services/Loot/Snapshots.lua")
    h:load("!KRT/Services/Loot/PendingAwards.lua")
    h:load("!KRT/Services/Loot/PassiveGroupLoot.lua")
    h:load("!KRT/Services/Loot/Tracking.lua")
    h:load("!KRT/Services/Loot/Workflow.lua")
    h:load("!KRT/Services/Loot/Receipts.lua")
    h:load("!KRT/Services/Loot/Records.lua")
    h:load("!KRT/Services/Loot/Reconcile.lua")
    h:load("!KRT/Services/Loot/Rules.lua")
    h:load("!KRT/Services/Loot/Service.lua")

    local loot = h.addon.Services.Loot
    local model = loot:GetDistributionSessionModel()

    assertTrue(loot._DistributionSession ~= nil, "expected service fallback to install a distribution helper table")
    assertEqual(#model.rows, 0, "expected fallback display model to be empty")
    assertTrue(loot:HandleDistributionMessage("KRTDist", "ITEM|2|session-1|item:1", "RAID", "ML") == false, "expected fallback to ignore distribution messages")
    assertTrue(loot:SetDistributionState("session") == false, "expected fallback session reset to be a no-op")
    assertTrue(loot:SetDistributionState("roll_start", {
        itemLink = "item:1",
        rollType = h.rollTypes.MAINSPEC,
        duration = 30,
    }) == false, "expected fallback roll start to be a no-op")
    assertTrue(loot:SetDistributionState("roll_end", {
        itemLink = "item:1",
        winnerName = "Alice",
        rollValue = 98,
        reason = "test",
    }) == false, "expected fallback roll end to be a no-op")
    assertTrue(loot:SetDistributionState("item_done", {
        itemLink = "item:1",
        winnerName = "Alice",
    }) == false, "expected fallback item done to be a no-op")
    assertTrue(loot:SetDistributionState("unknown") == false, "expected unknown distribution states to be ignored")
end)

test("comms sync reports unavailable group transport", function()
    local h = newHarness()
    local sent = {}
    _G.GetNumRaidMembers = function()
        return 0
    end
    _G.GetNumPartyMembers = function()
        return 0
    end
    _G.SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = target,
        }
    end

    h:load("!KRT/Modules/Comms.lua")

    local ok = h.addon.Comms.Sync("KRTTest", "payload")

    assertTrue(ok == false, "expected sync to report missing group transport")
    assertEqual(#sent, 0, "expected no addon message outside party, raid, or battleground")
end)

test("reserves synced runtime cache feeds display without persisting", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local ok = Reserves:SetSyncedData({
        Alice = {
            reserves = {
                { rawID = 1001, quantity = 2, plus = 4, class = "MAGE" },
            },
        },
    }, {
        source = "Master",
        checksum = "abc123",
        mode = "plus",
    })

    assertTrue(ok == true, "expected synced reserves cache to be accepted without local data")
    assertTrue(Reserves:HasData() == true, "expected synced runtime cache to count as display data")
    assertTrue(Reserves:IsLocalDataAvailable() ~= true, "expected synced runtime cache to remain non-local")
    assertEqual(Reserves:FormatReservedPlayersLine(1001, false, true, true), "Alice (P+4)", "expected synced cache to feed reserve display")

    local meta = Reserves:GetSyncMetadata()
    assertEqual(meta.source, "Master", "expected sync metadata source")
    assertEqual(meta.checksum, "abc123", "expected sync metadata checksum")
    assertEqual(meta.players, 1, "expected sync metadata player count")
    assertEqual(meta.entries, 1, "expected sync metadata entry count")
    assertTrue(meta.runtime == true, "expected sync metadata to mark runtime cache")

    Reserves:Save("test")
    assertEqual(_G.KRT_Reserves.Alice, nil, "expected synced runtime cache to avoid SavedVariables persistence")
end)

test("reserves local data wins over synced runtime cache", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, quantity = 1 },
            },
        },
    }
    h:load("!KRT/Services/Reserves.lua")

    local Reserves = h.addon.Services.Reserves
    Reserves:Load()

    local ok, reason = Reserves:SetSyncedData({
        Bob = {
            reserves = {
                { rawID = 2002, quantity = 1 },
            },
        },
    }, {
        source = "Master",
        checksum = "synced",
        mode = "multi",
    })

    assertTrue(ok ~= true, "expected synced cache to be rejected when local reserves exist")
    assertEqual(reason, "local_data_present", "expected local-data rejection reason")
    assertTrue(Reserves:IsLocalDataAvailable() == true, "expected local reserves to remain authoritative")
    assertEqual(Reserves:FormatReservedPlayersLine(1001, false, true, true), "Alice", "expected local reserve display to remain active")
    assertEqual(Reserves:FormatReservedPlayersLine(2002, false, true, true), "", "expected rejected synced cache to stay hidden")
end)

test("reserves service exposes count facade for entrypoints", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { item = "A" },
                { item = "B" },
            },
        },
        Bob = {
            reserves = {
                { item = "C" },
            },
        },
    }

    h:load("!KRT/Services/Reserves.lua")

    local players, entries = h.addon.Services.Reserves:GetCounts(_G.KRT_Reserves)
    assertEqual(players, 2, "expected reserve player count")
    assertEqual(entries, 3, "expected reserve entry count")

    players, entries = h.addon.Services.Reserves:GetCounts()
    assertEqual(players, 2, "expected default reserve player count from SavedVariables")
    assertEqual(entries, 3, "expected default reserve entry count from SavedVariables")

    _G.KRT_Reserves = "bad"
    players, entries = h.addon.Services.Reserves:GetCounts()
    assertEqual(players, 0, "expected malformed default reserve store to report zero players")
    assertEqual(entries, 0, "expected malformed default reserve store to report zero entries")

    players, entries = h.addon.Services.Reserves:GetCounts(false)
    assertEqual(players, 0, "expected malformed explicit reserve store to report zero players")
    assertEqual(entries, 0, "expected malformed explicit reserve store to report zero entries")
end)

test("reserves service persists quantity edits and updates display rows", function()
    local h = newHarness()
    _G.KRT_Reserves = {
        Alice = {
            playerNameDisplay = "Alice",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 2, plus = 1 },
            },
        },
    }
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves
    Service:Load()

    local changed, reason = Service:SetPlayerReserveQuantity("Alice", 1201, 5)
    assertTrue(changed == true, "expected existing reserve quantity edit to succeed")
    assertTrue(reason == nil or reason == "no_change", "expected no error reason on successful quantity edit")

    local list = Service:GetDisplayList()
    local player = list[1] and list[1].players and list[1].players[1]
    assertEqual(player.quantity, 5, "expected display row quantity to update after edit")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].quantity, 5, "expected persisted quantity to update")
end)

test("reserves service persists plus edits and updates display rows", function()
    local h = newHarness()
    setHarnessOption(h, "Reserves", "srImportMode", 1, { srImportMode = 0 })
    _G.KRT_Reserves = {
        Alice = {
            playerNameDisplay = "Alice",
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 1, plus = 1 },
            },
        },
    }
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")

    local Service = h.addon.Services.Reserves
    Service:Load()

    local changed = Service:SetPlayerReservePlus("Alice", 1201, 9)
    assertTrue(changed == true, "expected existing reserve plus edit to succeed")

    local list = Service:GetDisplayList()
    local player = list[1] and list[1].players and list[1].players[1]
    assertEqual(player.plus, 9, "expected display row plus to update after edit")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].plus, 9, "expected persisted plus to update")
end)

test("reserves service promotes synced runtime cache and removes player rows on remove", function()
    local h = newHarness()
    _G.KRT_Reserves = {}
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Modules/C.lua")

    local Service = h.addon.Services.Reserves
    Service:Load()

    local syncSet = Service:SetSyncedData({
        Alice = {
            reserves = {
                { rawID = 1201, itemName = "Coldsteel Dagger", quantity = 2, plus = 1 },
                { rawID = 1202, itemName = "Frost Edge", quantity = 1, plus = 0 },
            },
        },
    }, { source = "Master", mode = "multi" })
    assertTrue(syncSet == true, "expected runtime synced cache to load for test")

    local changed = Service:SetPlayerReserveQuantity("Alice", 1201, 3)
    assertTrue(changed == true, "expected synced cache edit to promote and change local reserve")
    assertTrue(Service:IsLocalDataAvailable() == true, "expected edited synced cache to become local")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].rawID, 1201, "expected local data to persist after edit")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].quantity, 3, "expected edited quantity to persist")
    assertEqual(_G.KRT_Reserves.Alice.reserves[2].rawID, 1202, "expected non-edited synced row to persist")

    local removeOk = Service:RemovePlayerReserve("Alice", 1202)
    assertTrue(removeOk == true, "expected remove to delete player item reserve")
    assertTrue(_G.KRT_Reserves.Alice, "expected player to remain while one reserve still exists")

    local removeLast = Service:RemovePlayerReserve("Alice", 1201)
    assertTrue(removeLast == true, "expected removing final player reserve to delete player container")
    assertEqual(_G.KRT_Reserves.Alice, nil, "expected player container removed when no reserves remain")
    assertTrue(Service:HasData() == false, "expected all reserve data removed after final delete")
end)

test("reserves whisper softres ignores requests while disabled", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1001:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", quantity = 1 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "softResWhisperReplies", false, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr", "Alice")

    assertTrue(handled == true, "expected SoftRes request command to be recognized")
    assertEqual(#sent, 0, "expected disabled whisper replies to stay silent")
end)

test("reserves whisper softres replies with player reserves for authorized holders", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1001:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", quantity = 2 },
                { rawID = 1002, itemName = "Frost Edge", itemLink = "|cffa335ee|Hitem:1002:0:0:0:0:0:0:0|h[Frost Edge]|h|r", plus = 4 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+softres", "Alice")

    assertTrue(handled == true, "expected +softres command to be recognized")
    assertTrue(#sent >= 3, "expected header and reserve lines")
    assertEqual(sent[1].target, "Alice", "expected reply target to be the requester")
    assertEqual(sent[1].msg, "Your SoftRes reserves:", "expected concise player-facing SoftRes header")
    assertTextNotContains(sent[2].msg, "KRT SoftRes:", "expected reserve line to omit addon prefix")
    assertTrue(string.find(sent[2].msg, "Coldsteel Dagger", 1, true) ~= nil, "expected first reserve item in reply")
    assertTrue(string.find(sent[2].msg, "x2", 1, true) ~= nil, "expected multi-reserve quantity in reply")
    assertTrue(string.find(sent[3].msg, "Frost Edge", 1, true) ~= nil, "expected second reserve item in reply")
    assertTextNotContains(sent[3].msg, "P+4", "expected plus value to be omitted in multi-mode reply")
    for i = 1, #sent do
        assertTrue(string.len(sent[i].msg) <= 255, "expected whisper line to stay chat-safe")
    end
end)

test("reserves whisper softres replies with plus suffix in plus mode", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", itemLink = "|cff0070dd|Hitem:1001:0:0:0:0:0:0:0|h[Coldsteel Dagger]|h|r", plus = 4 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "srImportMode", 1, { srImportMode = 0 })
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr", "Alice")

    assertTrue(handled == true, "expected +sr command to be recognized")
    assertTrue(#sent >= 2, "expected header and reserve line")
    assertTrue(string.find(sent[2].msg, "P+4", 1, true) ~= nil, "expected plus value in plus-mode reply")
end)

test("reserves whisper softres accepts advertised aliases", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", quantity = 1 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h.addon.Events.Wow = { ChatMsgWhisper = "wow.CHAT_MSG_WHISPER" }
    h:setRaidRoleState({ inRaid = true, rank = 1, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local aliases = { "+sr", "+softres" }
    for i = 1, #aliases do
        sent = {}
        local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply(aliases[i], "Alice")
        assertTrue(handled == true, "expected SoftRes whisper alias to be recognized")
        assertTrue(#sent >= 2, "expected alias to send reserve reply")
        assertTrue(string.find(sent[2].msg, "Coldsteel Dagger", 1, true) ~= nil, "expected reserve item in alias reply")
    end

    sent = {}
    h.Bus.TriggerEvent("wow.CHAT_MSG_WHISPER", "+sr", "Alice")
    assertTrue(#sent >= 2, "expected whisper bus event to route to the reserve reply handler")

    local legacyAliases = { "!sr", "!softres", "sr", "softres", "krt sr", "krt softres" }
    for i = 1, #legacyAliases do
        sent = {}
        local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply(legacyAliases[i], "Alice")
        assertTrue(handled ~= true, "expected non-advertised SoftRes whisper alias to be ignored")
        assertEqual(#sent, 0, "expected ignored SoftRes whisper alias to stay silent")
    end
end)

test("reserves whisper softres adds an item reserve and replies with success", function()
    local h = newHarness()
    local sent = {}
    local changed = {}
    local itemLink = h.registerItem(39717, "Inexorable Sabatons", 4, "Icon39717")
    _G.KRT_Reserves = {}
    setHarnessOption(h, "Reserves", "softResWhisperAdds", true, { softResWhisperAdds = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [39717] = {
            {
                npcId = 37813,
                npcName = "Deathbringer Saurfang",
                raid = "Icecrown Citadel",
                kind = "boss",
            },
        },
    })
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()
    h.Bus.RegisterCallback(h.addon.Events.Internal.ReservesDataChanged, function(_, reason)
        changed[#changed + 1] = reason
    end)

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+SOFTRES   " .. itemLink, "Alice")
    local entries = h.addon.Services.Reserves:GetPlayerReserveEntries("Alice")

    assertTrue(handled == true, "expected +softres item command to be recognized")
    assertEqual(#sent, 1, "expected one confirmation whisper")
    assertEqual(sent[1].target, "Alice", "expected confirmation to target the requester")
    assertEqual(sent[1].msg, "Your " .. itemLink .. " reserve is added!", "expected item reserve confirmation")
    assertEqual(#entries, 1, "expected one reserve entry for the whisper sender")
    assertEqual(entries[1].rawID, 39717, "expected added reserve item id")
    assertEqual(entries[1].itemLink, itemLink, "expected added reserve to keep the item link")
    assertEqual(entries[1].source, "Deathbringer Saurfang", "expected added reserve to resolve the item source")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].rawID, 39717, "expected added reserve to persist")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].source, "Deathbringer Saurfang", "expected persisted source to avoid whisper grouping")
    assertEqual(changed[1], "whisper-reserve", "expected reserve views to refresh after whisper add")
end)

test("reserves whisper softres stores shared source for ambiguous item reserves", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(39717, "Inexorable Sabatons", 4, "Icon39717")
    _G.KRT_Reserves = {}
    setHarnessOption(h, "Reserves", "softResWhisperAdds", true, { softResWhisperAdds = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Modules/LootSources.lua")
    h.addon.LootSources._SetDataForTests({
        [39717] = {
            { npcId = 15956, npcName = "Anub'Rekhan", raid = "Naxxramas", kind = "boss" },
            { npcId = 15932, npcName = "Gluth", raid = "Naxxramas", kind = "boss" },
        },
    })
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+SR   " .. itemLink, "Alice")
    local entries = h.addon.Services.Reserves:GetPlayerReserveEntries("Alice")

    assertTrue(handled == true, "expected +sr item command to be recognized")
    assertEqual(#sent, 1, "expected one confirmation whisper for shared-source item")
    assertEqual(#entries, 1, "expected one shared-source reserve entry")
    assertEqual(entries[1].source, "Shared", "expected ambiguous item source to avoid a fake whisper group")
    assertEqual(_G.KRT_Reserves.Alice.reserves[1].source, "Shared", "expected shared source to persist")
end)

test("reserves whisper softres reports invalid item links for add requests", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {}
    setHarnessOption(h, "Reserves", "softResWhisperAdds", true, { softResWhisperAdds = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+SOFTRES   [Unknown Item]", "Alice")

    assertTrue(handled == true, "expected invalid add request to be handled")
    assertEqual(#sent, 1, "expected invalid add request to reply once")
    assertEqual(sent[1].msg, "Shift-click an item link after +sr or +softres to add a reserve.", "expected item-link help")
    assertEqual(h.addon.Services.Reserves:HasData(), false, "expected invalid add request to avoid creating reserves")
end)

test("reserves whisper softres requires add option to add reserves", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(39717, "Inexorable Sabatons", 4, "Icon39717")
    _G.KRT_Reserves = {}
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, { softResWhisperAdds = false })
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Modules/LootSources.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })
    h.addon.Services.Reserves:Load()
    h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr " .. itemLink, "Alice")
    assertEqual(h.addon.Services.Reserves:HasData(), false, "expected add requests to be blocked when add option is disabled")
    assertEqual(#sent, 0, "expected disabled add option to produce no add whisper response")
    setHarnessOption(h, "Reserves", "softResWhisperAdds", true, { softResWhisperAdds = true })
    h:load("!KRT/Localization/localization.en.lua")
    h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr " .. itemLink, "Alice")
    local entries = h.addon.Services.Reserves:GetPlayerReserveEntries("Alice")
    assertTrue(entries[1] ~= nil, "expected add requests to persist when add option is enabled")
end)

test("reserves whisper softres does not add reserves when only reply option is enabled", function()
    local h = newHarness()
    local sent = {}
    local itemLink = h.registerItem(39717, "Inexorable Sabatons", 4, "Icon39717")
    _G.KRT_Reserves = {}
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, { softResWhisperAdds = false })
    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })
    h.addon.Services.Reserves:Load()

    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr " .. itemLink, "Alice")

    assertTrue(handled == true, "expected add command to be handled when reply option is enabled")
    assertEqual(#sent, 0, "expected add request to stay silent when add option is disabled")
    assertEqual(h.addon.Services.Reserves:HasData(), false, "expected no reserves to be added when add option is disabled")
end)

test("reserves whisper softres replies without add option only when reply option enabled", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", quantity = 1 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    setHarnessOption(h, "Reserves", "softResWhisperAdds", false, { softResWhisperAdds = false })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Modules/C.lua")
    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr", "Alice")

    assertTrue(handled == true, "expected query command to be handled with replies enabled")
    assertTrue(#sent >= 1, "expected reserve query reply to still happen when add option is disabled")
end)

test("reserves whisper softres denies normal raiders even with reserve data", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, itemName = "Coldsteel Dagger", quantity = 1 },
            },
        },
    }
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 0, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+sr", "Alice")

    assertTrue(handled == true, "expected SoftRes request command to be recognized")
    assertEqual(#sent, 0, "expected normal raiders to stay silent even with reserve data")
end)

test("reserves whisper softres replies no reserves without reserve data", function()
    local h = newHarness()
    local sent = {}
    _G.KRT_Reserves = {}
    setHarnessOption(h, "Reserves", "softResWhisperReplies", true, { softResWhisperReplies = true })
    h.addon.Comms.SendWhisper = function(target, msg)
        sent[#sent + 1] = { target = target, msg = msg }
        return true
    end
    h:setRaidRoleState({ inRaid = true, rank = 2, isMasterLooter = false })

    h:load("!KRT/Localization/localization.en.lua")
    h:load("!KRT/Services/Reserves.lua")
    h:load("!KRT/Services/Reserves/Chat.lua")
    h.addon.Services.Reserves:Load()

    local handled = h.addon.Services.Reserves._Chat:RequestWhisperReply("+SR", "Alice")

    assertTrue(handled == true, "expected case-insensitive command to be recognized")
    assertEqual(#sent, 1, "expected clients without reserve data to send an empty result")
    assertEqual(sent[1].target, "Alice", "expected empty result to target the requester")
    assertEqual(sent[1].msg, "No reserves found for Alice.", "expected no-reserves feedback")
end)

test("reserves sync helper requests metadata and imports chunked runtime data", function()
    local requester = newHarness()
    local provider = newHarness()
    local sent = {}
    _G.GetNumRaidMembers = function()
        return 10
    end
    _G.SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = target,
        }
    end

    _G.KRT_Reserves = {}
    requester:load("!KRT/Localization/localization.en.lua")
    requester:load("!KRT/Modules/Comms.lua")
    requester:load("!KRT/Services/Reserves.lua")
    requester.addon.Services.Reserves:Load()

    local ok = requester.addon.Services.Reserves:RequestSyncMetadata()

    assertTrue(ok == true, "expected metadata request to be sent")
    assertEqual(sent[1].prefix, "KRTResSync", "expected dedicated reserves sync prefix")
    assertEqual(sent[1].channel, "RAID", "expected group metadata request")
    assertTrue(sent[1].msg:match("^META_REQ|") ~= nil, "expected metadata request payload")

    sent = {}
    _G.KRT_Reserves = {
        Alice = {
            reserves = {
                { rawID = 1001, quantity = 1, plus = 2 },
            },
        },
    }
    provider:load("!KRT/Localization/localization.en.lua")
    provider:load("!KRT/Modules/Comms.lua")
    provider:load("!KRT/Services/Reserves.lua")
    provider.addon.Services.Reserves:Load()
    provider:setRaidRoleState({ inRaid = true, isLeader = true, isMasterLooter = true })

    local handled = provider.addon.Services.Reserves:HandleSyncMessage("KRTResSync", "META_REQ|1", "RAID", "Requester")

    assertTrue(handled == true, "expected provider to handle metadata request")
    assertEqual(sent[1].prefix, "KRTResSync", "expected provider metadata prefix")
    assertEqual(sent[1].channel, "WHISPER", "expected provider to whisper metadata")
    assertEqual(sent[1].target, "Requester", "expected provider to target requester")
    assertTrue(sent[1].msg:match("^META_ACK|") ~= nil, "expected metadata ack")

    local metaAck = sent[1]
    sent = {}
    requester.addon.Services.Reserves:HandleSyncMessage(metaAck.prefix, metaAck.msg, metaAck.channel, "Master")

    assertEqual(sent[1].prefix, "KRTResSync", "expected requester data request prefix")
    assertEqual(sent[1].channel, "WHISPER", "expected requester to whisper data request")
    assertEqual(sent[1].target, "Master", "expected requester to target metadata provider")
    assertTrue(sent[1].msg:match("^DATA_REQ|") ~= nil, "expected metadata ack to trigger data request")

    local dataReq = sent[1]
    sent = {}
    provider.addon.Services.Reserves:HandleSyncMessage(dataReq.prefix, dataReq.msg, dataReq.channel, "Requester")

    assertTrue(#sent >= 2, "expected data chunks and done message after data request")
    assertTrue(sent[#sent].msg:match("^DATA_DONE|") ~= nil, "expected final data done message")

    for i = 1, #sent do
        requester.addon.Services.Reserves:HandleSyncMessage(sent[i].prefix, sent[i].msg, sent[i].channel, "Master")
    end
    assertEqual(requester.addon.Services.Reserves:FormatReservedPlayersLine(1001, false, true, true), "Alice", "expected chunked sync payload to populate requester runtime cache")
    requester.addon.Services.Reserves:Save("test")
    assertEqual(_G.KRT_Reserves.Alice, nil, "expected chunked sync payload to remain non-persistent")
end)

test("reserves sync compact payload reduces repeated player names and imports", function()
    local provider = newHarness()
    local requester = newHarness()
    local sent = {}
    _G.SendAddonMessage = function(prefix, msg, channel, target)
        sent[#sent + 1] = {
            prefix = prefix,
            msg = msg,
            channel = channel,
            target = target,
        }
    end

    _G.KRT_Reserves = {
        ["Longplayername"] = {
            playerNameDisplay = "Longplayername",
            reserves = {
                { rawID = 1001, quantity = 1, plus = 2, class = "MAGE" },
                { rawID = 1002, quantity = 1, plus = 3, class = "MAGE" },
                { rawID = 1003, quantity = 1, plus = 4, class = "MAGE" },
            },
        },
    }
    provider:load("!KRT/Localization/localization.en.lua")
    provider:load("!KRT/Modules/Comms.lua")
    provider:load("!KRT/Services/Reserves.lua")
    provider.addon.Services.Reserves:Load()
    provider:setRaidRoleState({ inRaid = true, isLeader = true, isMasterLooter = true })

    provider.addon.Services.Reserves:HandleSyncMessage("KRTResSync", "DATA_REQ|legacy|checksum", "WHISPER", "Requester")
    local legacyBytes = 0
    for i = 1, #sent do
        if sent[i].msg:match("^DATA_CHUNK|") then
            legacyBytes = legacyBytes + string.len(sent[i].msg)
        end
    end

    sent = {}
    provider.addon.Services.Reserves:HandleSyncMessage("KRTResSync", "DATA_REQ|compact|checksum|C1", "WHISPER", "Requester")
    local compactBytes = 0
    local compactMessages = {}
    for i = 1, #sent do
        if sent[i].msg:match("^DATA_CHUNK|") then
            compactBytes = compactBytes + string.len(sent[i].msg)
        end
        compactMessages[#compactMessages + 1] = sent[i]
    end

    assertTrue(compactBytes < legacyBytes, "expected compact reserve sync payload to reduce repeated player-name bytes")

    _G.KRT_Reserves = {}
    requester:load("!KRT/Localization/localization.en.lua")
    requester:load("!KRT/Modules/Comms.lua")
    requester:load("!KRT/Services/Reserves.lua")
    requester.addon.Services.Reserves:Load()

    for i = 1, #compactMessages do
        requester.addon.Services.Reserves:HandleSyncMessage(compactMessages[i].prefix, compactMessages[i].msg, compactMessages[i].channel, "Master")
    end

    assertEqual(
        requester.addon.Services.Reserves:FormatReservedPlayersLine(1002, false, true, true),
        "Longplayername",
        "expected compact reserve sync payload to import runtime cache"
    )
end)

test("spec inspect service source is checked for modern talent refresh", function()
    local ok, specInspectSource = pcall(readText, "!KRT/Services/SpecInspect.lua")
    assertTrue(ok, "expected SpecInspect service source file to exist")

    assertTextContains(specInspectSource, 'LibStub("LibGroupTalents-1.0", true)', "expected LibGroupTalents dependency")
    assertTextNotContains(specInspectSource, "NotifyInspect(", "must avoid deprecated unit inspect API")
    assertTextContains(specInspectSource, "RefreshTalentsByUnit", "must use LibGroupTalents refresh API")
end)

local failures = 0
for i = 1, #tests do
    local entry = tests[i]
    io.write("[TEST] ", entry.name, "\n")
    local ok, err = pcall(entry.fn)
    if ok then
        io.write("  OK\n")
    else
        failures = failures + 1
        io.write("  FAIL: ", tostring(err), "\n")
    end
end

if failures > 0 then
    io.write(string.format("\n%d targeted stabilization test(s) failed.\n", failures))
    os.exit(1)
end

io.write(string.format("\n%d targeted stabilization test(s) passed.\n", #tests))
