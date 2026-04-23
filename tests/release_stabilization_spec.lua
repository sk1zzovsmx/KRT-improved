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

    function frame:SetTextInsets() end

    function frame:SetJustifyH() end

    function frame:SetJustifyV() end

    function frame:SetFontObject() end

    function frame:GetStringHeight()
        return string.len(self.text or "")
    end

    function frame:SetParent(parent)
        self.parent = parent
    end

    function frame:ClearAllPoints() end

    function frame:SetPoint() end

    function frame:SetFrameLevel(level)
        self._frameLevel = level
    end

    function frame:GetFrameLevel()
        return self._frameLevel or 1
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

    function bus.RegisterCallbacks(eventNames, callback)
        if type(eventNames) ~= "table" then
            return
        end
        for i = 1, #eventNames do
            bus.RegisterCallback(eventNames[i], callback)
        end
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

    if type(tbl.ClearRaidChanges) ~= "function" then
        function tbl:ClearRaidChanges()
            return true, 0
        end
    end

    if type(tbl.DeleteRaidChange) ~= "function" then
        function tbl:DeleteRaidChange()
            return true, false
        end
    end

    if type(tbl.CanBroadcastChanges) ~= "function" then
        function tbl:CanBroadcastChanges()
            return true, nil
        end
    end

    if type(tbl.BuildRaidChangesDemandText) ~= "function" then
        function tbl:BuildRaidChangesDemandText()
            return "Demand"
        end
    end

    if type(tbl.BuildRaidChangesAnnouncement) ~= "function" then
        function tbl:BuildRaidChangesAnnouncement(changesByName)
            local count = 0
            for _ in pairs(changesByName or {}) do
                count = count + 1
            end
            return count > 0 and "Announce" or "None", count
        end
    end

    if type(tbl.GetRaidChanges) ~= "function" then
        function tbl:GetRaidChanges()
            return {}
        end
    end

    if type(tbl.UpsertRaidChange) ~= "function" then
        function tbl:UpsertRaidChange(_, playerName, spec)
            return true, playerName, spec
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

    if type(tbl.SendSpamOutput) ~= "function" then
        function tbl:SendSpamOutput(_output, _channels)
            return true
        end
    end

    if type(tbl.BuildSpammerOutput) ~= "function" then
        function tbl:BuildSpammerOutput(_state, defaultOutput)
            return defaultOutput or "LFM"
        end
    end

    return tbl
end

local function newHarness()
    installTableHelpers()

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
    Diag.E.LogLoggerLootNidExpected = "[Logger] Loot:SetLootEntry expected lootNid but got raw itemId raidId=%s value=%s link=%s matches=%d"
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
    function Strings.NormalizeName(name)
        if type(name) ~= "string" then
            return nil
        end
        local out = name:gsub("^%s+", ""):gsub("%s+$", "")
        if out == "" then
            return nil
        end
        return out
    end

    function Strings.NormalizeLower(name)
        local out = Strings.NormalizeName(name)
        return out and string.lower(out) or nil
    end

    function Strings.GetNormalizedNameLower(value)
        return Strings.NormalizeLower(value, true)
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
        HighestRoll = function()
            return 0
        end,
        GetRollSession = function()
            return nil
        end,
        RollStatus = function()
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
        UIPrimitives = {},
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
        return tostring(value)
    end
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

        if capability == "raid_leadership" or capability == "changes_broadcast" or capability == "raid_warning" or capability == "raid_icons" then
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

    addon.UI = {
        IsEnabled = function()
            return true
        end,
        Register = function() end,
        Call = function() end,
    }

    addon.UIPrimitives.EnableDisable = function(frame, enabled)
        if frame then
            frame._enabled = enabled and true or false
        end
    end

    addon.UIPrimitives.SetButtonGlow = function(frame, enabled)
        if frame then
            frame._glow = enabled and true or false
        end
    end

    addon.UIPrimitives.Toggle = function(frame)
        if not frame then
            return
        end
        if frame:IsVisible() then
            frame:Hide()
        else
            frame:Show()
        end
    end

    addon.UIPrimitives.ShowHide = function(frame, shown)
        if not frame then
            return
        end
        if shown then
            frame:Show()
        else
            frame:Hide()
        end
    end

    addon.UIRowVisuals = {
        EnsureRowVisuals = function() end,
        SetRowSelected = function() end,
        SetRowFocused = function() end,
    }

    addon.Comms = {
        Sync = function() end,
        Whisper = function() end,
    }

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

    addon.UIScaffold = {
        EnsureModuleUi = function(module)
            module._ui = module._ui
                or {
                    Loaded = false,
                    Bound = false,
                    Localized = false,
                    Dirty = true,
                    Reason = nil,
                    FrameName = nil,
                }
            return module._ui
        end,
        DefineModuleUi = function() end,
        MakeStandardWidgetApi = function(_, api)
            return api or {}
        end,
    }

    addon.Frames = {
        Get = function(name)
            return _G[name]
        end,
        Ref = function(frame, suffix)
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
        InitModuleFrame = function(module, frame)
            module.frame = frame
            return frame and frame.GetName and frame:GetName() or "TestFrame"
        end,
        SetFrameTitle = function() end,
        SafeSetScript = function(frame, scriptType, callback)
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
        MakeEditBoxPopup = function(name, _, onAccept, onShow, validate)
            _G[name] = {
                onAccept = onAccept,
                onShow = onShow,
                validate = validate,
            }
        end,
        SetTooltip = function() end,
        SetEditBoxValue = function(editBox, value)
            if editBox and editBox.SetText then
                editBox:SetText(tostring(value or ""))
            end
        end,
        BindEditBoxHandlers = function(frameName, specs, requestRefreshFn)
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
        ResetEditBox = function(editBox)
            if editBox and editBox.SetText then
                editBox:SetText("")
            end
        end,
    }

    addon.ListController = {
        CreateRowDrawer = function(fn)
            return function(row, it)
                return fn(row, it)
            end
        end,
        MakeListController = function(cfg)
            local controller = { cfg = cfg, dirtyCount = 0 }
            function controller:Dirty()
                self.dirtyCount = self.dirtyCount + 1
            end

            function controller:Touch()
                self:Dirty()
            end

            function controller:_makeConfirmPopup() end

            return controller
        end,
        BindListController = function(target, controller)
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

    addon.MultiSelect = {
        MultiSelectSetModifierPolicy = function() end,
        MultiSelectSetAnchor = function() end,
        MultiSelectCount = function()
            return 0
        end,
        MultiSelectGetSelected = function()
            return {}
        end,
        MultiSelectClear = function() end,
        MultiSelectToggle = function(_, id)
            return "toggle", (id and 1 or 0)
        end,
        MultiSelectGetAnchor = function()
            return nil
        end,
    }

    local Core = {}
    local feature = {
        L = L,
        Diag = Diag,
        Frames = addon.Frames,
        Events = Events,
        C = C,
        Core = Core,
        Options = {
            IsDebugEnabled = function()
                return addon.State.debugEnabled == true
            end,
            SetOption = function(key, value)
                addon.options[key] = value
            end,
        },
        Bus = Bus,
        Strings = Strings,
        Colors = addon.Colors,
        Base64 = addon.Base64,
        Sort = Sort,
        ListController = addon.ListController,
        MultiSelect = addon.MultiSelect,
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

    addon.Options = feature.Options
    addon.Time = feature.Time
    addon.Bus = Bus
    addon.Core = Core
    addon.Core.GetFeatureShared = function()
        return feature
    end
    Core.GetFeatureShared = addon.Core.GetFeatureShared
    Core.GetCurrentRaid = function()
        return addon.State.currentRaid
    end
    Core.GetLastBoss = function()
        return addon.State.lastBoss
    end
    Core.SetLastBoss = function(bossNid)
        addon.State.lastBoss = bossNid
        return addon.State.lastBoss
    end
    Core.GetPlayerName = function()
        return "Tester"
    end
    Core.GetRaidSchemaVersion = function()
        return 1
    end
    Core.GetRaidMigrations = function()
        return nil
    end
    Core.GetRaidQueries = function()
        return nil
    end
    Core.GetRaidStoreOrNil = function()
        return nil
    end
    Core.RequireServiceMethod = function(serviceName, serviceTable, methodName)
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

    local function ensureLootContextHelpers()
        local lootContext = addon.Core._LootContext
        if type(lootContext) == "table" and type(lootContext.NormalizeActiveLootContext) == "function" then
            return lootContext
        end

        lootContext = lootContext or {}
        addon.Core._LootContext = lootContext

        local function isValidLootSourceKind(kind)
            return kind == "boss" or kind == "trash" or kind == "object"
        end

        local function hasActiveLootSource(context)
            if type(context) ~= "table" or not isValidLootSourceKind(context.kind) then
                return false
            end
            if context.kind == "object" then
                return true
            end
            return context.blocked == true or (tonumber(context.bossNid) or 0) > 0
        end

        local function hasActiveLootWindow(context)
            if type(context) ~= "table" then
                return false
            end
            local windowExpiresAt = tonumber(context.windowExpiresAt) or 0
            if windowExpiresAt <= 0 then
                return false
            end
            if context.blocked == true then
                return true
            end
            return (tonumber(context.bossNid) or 0) > 0
        end

        function lootContext.NormalizeBossEventContext(context)
            if type(context) ~= "table" then
                return nil
            end
            context.raidNum = tonumber(context.raidNum) or 0
            context.bossNid = tonumber(context.bossNid) or 0
            context.name = context.name or nil
            context.source = context.source or nil
            context.seenAt = tonumber(context.seenAt) or 0
            if context.bossNid <= 0 or context.raidNum <= 0 then
                return nil
            end
            return context
        end

        function lootContext.NormalizeLootWindowBossContext(context)
            if type(context) ~= "table" then
                return nil
            end
            context.raidNum = tonumber(context.raidNum) or 0
            context.bossNid = tonumber(context.bossNid) or 0
            context.blocked = context.blocked == true
            context.source = context.source or nil
            context.sourceUnit = context.sourceUnit or nil
            context.sourceNpcId = tonumber(context.sourceNpcId) or 0
            context.sourceName = context.sourceName or nil
            context.expiresAt = tonumber(context.expiresAt) or 0
            if context.raidNum <= 0 then
                return nil
            end
            if context.blocked ~= true and context.bossNid <= 0 then
                return nil
            end
            return context
        end

        function lootContext.NormalizeLootSessionState(state)
            if type(state) ~= "table" then
                return nil
            end
            state.bySessionId = type(state.bySessionId) == "table" and state.bySessionId or {}
            return state
        end

        function lootContext.NormalizeLootSnapshotState(state)
            if type(state) ~= "table" then
                return nil
            end
            state.byId = type(state.byId) == "table" and state.byId or {}
            state.bySignature = type(state.bySignature) == "table" and state.bySignature or {}
            state.nextId = tonumber(state.nextId) or 1
            state.activeId = tonumber(state.activeId) or nil
            state.nextPurgeAt = tonumber(state.nextPurgeAt) or 0
            state.signatureIndexVersion = tonumber(state.signatureIndexVersion) or 0
            if state.nextId < 1 then
                state.nextId = 1
            end
            return state
        end

        function lootContext.NormalizeLootSourceState(state)
            if type(state) ~= "table" then
                return nil
            end
            state.raidNum = tonumber(state.raidNum) or 0
            state.kind = isValidLootSourceKind(state.kind) and state.kind or nil
            state.bossNid = tonumber(state.bossNid) or 0
            state.sourceNpcId = tonumber(state.sourceNpcId) or 0
            state.sourceName = state.sourceName or nil
            state.openedAt = tonumber(state.openedAt) or 0
            state.snapshotId = tonumber(state.snapshotId) or nil
            state.expiresAt = tonumber(state.expiresAt) or 0
            if state.raidNum <= 0 or not state.kind then
                return nil
            end
            return state
        end

        function lootContext.NormalizeActiveLootContext(context)
            if type(context) ~= "table" then
                return nil
            end
            context.raidNum = tonumber(context.raidNum) or 0
            context.kind = isValidLootSourceKind(context.kind) and context.kind or nil
            context.bossNid = tonumber(context.bossNid) or 0
            context.blocked = context.blocked == true
            context.source = context.source or nil
            context.sourceUnit = context.sourceUnit or nil
            context.sourceNpcId = tonumber(context.sourceNpcId) or 0
            context.sourceName = context.sourceName or nil
            context.snapshotId = tonumber(context.snapshotId) or nil
            context.openedAt = tonumber(context.openedAt) or 0
            context.expiresAt = tonumber(context.expiresAt) or 0
            context.windowExpiresAt = tonumber(context.windowExpiresAt) or 0
            if context.raidNum <= 0 then
                return nil
            end

            local hasSource = hasActiveLootSource(context)
            local hasWindow = hasActiveLootWindow(context)
            if not hasSource and not hasWindow then
                return nil
            end

            if not hasSource then
                context.kind = nil
                context.snapshotId = nil
                context.openedAt = 0
                context.expiresAt = 0
            end
            if not hasWindow then
                context.blocked = false
                context.source = nil
                context.sourceUnit = nil
                context.windowExpiresAt = 0
            end

            return context
        end

        function lootContext.BuildActiveLootContext(activeLoot, lootWindowBossContext, lootSource)
            local context = lootContext.NormalizeActiveLootContext(activeLoot)
            if type(context) == "table" then
                return context
            end

            local activeWindow = lootContext.NormalizeLootWindowBossContext(lootWindowBossContext)
            local activeSource = lootContext.NormalizeLootSourceState(lootSource)
            if type(activeWindow) ~= "table" and type(activeSource) ~= "table" then
                return nil
            end

            return lootContext.NormalizeActiveLootContext({
                raidNum = tonumber(activeWindow and activeWindow.raidNum) or tonumber(activeSource and activeSource.raidNum) or 0,
                kind = activeSource and activeSource.kind or nil,
                bossNid = tonumber(activeWindow and activeWindow.bossNid) or tonumber(activeSource and activeSource.bossNid) or 0,
                blocked = activeWindow and activeWindow.blocked == true or false,
                source = activeWindow and activeWindow.source or nil,
                sourceUnit = activeWindow and activeWindow.sourceUnit or nil,
                sourceNpcId = tonumber(activeWindow and activeWindow.sourceNpcId) or tonumber(activeSource and activeSource.sourceNpcId) or 0,
                sourceName = (activeWindow and activeWindow.sourceName) or (activeSource and activeSource.sourceName) or nil,
                snapshotId = tonumber(activeSource and activeSource.snapshotId) or nil,
                openedAt = tonumber(activeSource and activeSource.openedAt) or 0,
                expiresAt = tonumber(activeSource and activeSource.expiresAt) or 0,
                windowExpiresAt = tonumber(activeWindow and activeWindow.expiresAt) or 0,
            })
        end

        function lootContext.ProjectLootWindowBossContext(context)
            context = lootContext.NormalizeActiveLootContext(context)
            if not hasActiveLootWindow(context) then
                return nil
            end

            return lootContext.NormalizeLootWindowBossContext({
                raidNum = tonumber(context.raidNum) or 0,
                bossNid = context.blocked == true and 0 or (tonumber(context.bossNid) or 0),
                blocked = context.blocked == true,
                source = context.source or nil,
                sourceUnit = context.sourceUnit or nil,
                sourceNpcId = tonumber(context.sourceNpcId) or 0,
                sourceName = context.sourceName or nil,
                expiresAt = tonumber(context.windowExpiresAt) or 0,
            })
        end

        function lootContext.ProjectLootSourceState(context)
            context = lootContext.NormalizeActiveLootContext(context)
            if not hasActiveLootSource(context) then
                return nil
            end

            local bossNid = tonumber(context.bossNid) or 0
            if context.kind == "object" then
                bossNid = 0
            end

            return lootContext.NormalizeLootSourceState({
                raidNum = tonumber(context.raidNum) or 0,
                kind = context.kind,
                bossNid = bossNid,
                sourceNpcId = tonumber(context.sourceNpcId) or 0,
                sourceName = context.sourceName or nil,
                openedAt = tonumber(context.openedAt) or 0,
                snapshotId = tonumber(context.snapshotId) or nil,
                expiresAt = tonumber(context.expiresAt) or 0,
            })
        end

        function lootContext.CopyLootSource(context, bossNidOverride)
            local source = lootContext.ProjectLootSourceState(context)
            if type(source) ~= "table" then
                return nil
            end

            local bossNid = tonumber(source.bossNid) or 0
            local overrideBossNid = tonumber(bossNidOverride) or 0
            if bossNid <= 0 and overrideBossNid > 0 and source.kind ~= "object" then
                bossNid = overrideBossNid
            end

            return {
                kind = source.kind,
                bossNid = bossNid,
                sourceNpcId = tonumber(source.sourceNpcId) or 0,
                sourceName = source.sourceName,
                openedAt = tonumber(source.openedAt) or 0,
                snapshotId = tonumber(source.snapshotId) or nil,
            }
        end

        return lootContext
    end

    local harness = {
        addon = addon,
        Core = Core,
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
                "!KRT/Services/Loot/Service.lua",
            }
            local raidServiceFiles = {
                "!KRT/Services/Raid/State.lua",
                "!KRT/Services/Raid/Capabilities.lua",
                "!KRT/Services/Raid/Counts.lua",
                "!KRT/Services/Raid/Roster.lua",
                "!KRT/Services/Raid/Attendance.lua",
                "!KRT/Services/Raid/LootRecords.lua",
                "!KRT/Services/Raid/Session.lua",
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

            if path == "!KRT/Services/Loot.lua" then
                loadFiles(lootServiceFiles)
                return addon.Services.Loot
            end

            if path == "!KRT/Services/Raid.lua" then
                ensureLootContextHelpers()
                loadFiles(lootServiceFiles)
                loadFiles(raidServiceFiles)
                local raid = addon.Services.Raid
                local loot = addon.Services.Loot
                if raid and loot then
                    -- Test harness compatibility: production moved passive/trade loot ingestion
                    -- to Services.Loot; keep legacy Raid call sites in existing tests functional.
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
                    "!KRT/Services/Rolls/Resolution.lua",
                    "!KRT/Services/Rolls/Display.lua",
                })
            end

            if path == "!KRT/Services/Reserves.lua" then
                loadFiles({
                    "!KRT/Services/Reserves/Import.lua",
                    "!KRT/Services/Reserves/Display.lua",
                })
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
        self:load("!KRT/Core/DBRaidStore.lua")
        local store = self.addon.DB.RaidStore
        store:NormalizeAllRaids()
        self.store = store
        self.Core.GetRaidStoreOrNil = function()
            return store
        end
        self.Core.EnsureRaidSchema = function(raid)
            return store:NormalizeRaidRecord(raid)
        end
        self.Core.StripRuntimeRaidCaches = function(raid)
            return store:StripRuntime(raid)
        end
        self.Core.EnsureRaidById = function(raidId)
            if not raidId then
                return nil
            end
            local raid = store:GetRaidByIndex(raidId)
            return raid and store:NormalizeRaidRecord(raid) or nil
        end
        self.Core.EnsureRaidByNid = function(raidNid)
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
    h.feature.MultiSelect = h.addon.MultiSelect

    local function getSelectedWinners()
        local selected = {}
        for i = 1, #order do
            local name = order[i]
            if h.addon.MultiSelect.MultiSelectIsSelected("MLRollWinners", name) then
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
        HighestRoll = function(_, winnerName)
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
        RecordRolls = function() end,
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

    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function() end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = #order
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true
    h.feature.lootState.winner = order[1]

    h.addon.MultiSelect.MultiSelectClear("MLRollWinners")
    for i = 1, #order do
        h.addon.MultiSelect.MultiSelectToggle("MLRollWinners", order[i], true)
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
    local currentModel = cfg.model or {}
    local candidates = cfg.candidates or { "Alice", "Bob", "Cara" }
    local candidateCache = {
        itemLink = nil,
        indexByName = {},
    }
    local queuedAwards = {}
    local givenLoot = {}
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
    _G.GetLootSlotLink = function(index)
        if index == 1 then
            return lootSlotLink
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
    h.feature.MultiSelect = h.addon.MultiSelect

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
        AddPendingAward = function(_, itemLinkArg, playerName, rollType, rollValue, sessionId)
            queuedAwards[#queuedAwards + 1] = {
                itemLink = itemLinkArg,
                playerName = playerName,
                rollType = rollType,
                rollValue = rollValue,
                sessionId = sessionId,
            }
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
        HighestRoll = function(_, winnerName)
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
        RecordRolls = function() end,
    }
    h:setRaidRoleState({
        inRaid = true,
        rank = 2,
        isMasterLooter = true,
    })
    h.feature.Services = h.addon.Services
    h.feature.RAID_TARGET_MARKERS = h.C.RAID_TARGET_MARKERS

    h:load("!KRT/Controllers/Master.lua")

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
        validationCalls = validationCalls,
        getRefreshCount = function()
            return refreshCount
        end,
    }
end

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

test("runtime cache reuses runtime until invalidated", function()
    local h = newHarness()
    h:load("!KRT/Core/DBRaidStore.lua")
    local store = h.addon.DB.RaidStore
    local raid = {
        schemaVersion = 1,
        raidNid = 1,
        players = {
            { playerNid = 1, name = "Alice", count = 0 },
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
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", join = 900, count = 2 },
                { playerNid = 2, name = "Bob", rank = 0, subgroup = 2, class = "WARRIOR", join = 900, count = 0 },
            },
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetRealmName = function()
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
    local raid = h.Core.EnsureRaidById(1)

    assertTrue(rosterChanged == true, "expected roster update to report a join/leave change")
    assertEqual(delta.joined[1].name, "Cara", "expected Cara to be reported as joined")
    assertEqual(delta.left[1].name, "Bob", "expected Bob to be reported as left")
    assertTrue(delta.updated == nil, "expected unchanged Alice to avoid an update delta")
    assertEqual(raid.players[1].name, "Alice", "expected Alice to stay in roster")
    assertEqual(raid.players[1].count, 2, "expected existing loot count to be preserved")
    assertEqual(raid.players[2].name, "Bob", "expected Bob row to stay persisted")
    assertTrue(tonumber(raid.players[2].leave) == 1000, "expected Bob to be marked left")
    assertEqual(raid.players[3].name, "Cara", "expected Cara to be added to roster")
    assertEqual(_G.KRT_Players.TestRealm.Cara.class, "PRIEST", "expected realm player metadata to be updated")
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
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", join = 900, count = 1 },
            },
            bossKills = {},
            loot = {},
            changes = {},
        },
    })
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetRealmName = function()
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
    local raid = h.Core.EnsureRaidById(1)

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
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", count = 0 },
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

    local raid = h.Core.EnsureRaidById(1)
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

test("logger builds attendance csv without replacing raid loot csv", function()
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
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 1, class = "MAGE", count = 0 },
            },
            attendance = {
                {
                    playerNid = 1,
                    segments = {
                        { startTime = 1000, endTime = 1010 },
                        { startTime = 1010, endTime = 1030, subgroup = 2, online = false },
                    },
                },
            },
            bossKills = {},
            loot = {},
            changes = {},
        },
    })

    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")

    local raid = h.Core.EnsureRaidById(1)
    local View = h.addon.Services.Logger.View
    local attendanceCsv = View:GetAttendanceCsv(raid, 1)
    local raidCsv = View:BuildRaidCsv(raid, 1)

    assertContains({ attendanceCsv }, "PlayerNID,Player,Class", "expected attendance csv to expose player columns")
    assertContains({ attendanceCsv }, "Alice,MAGE", "expected attendance csv to include the player")
    assertContains({ attendanceCsv }, "30,10,20,2", "expected attendance csv to summarize online and offline seconds")
    assertTrue(type(raidCsv) == "string", "expected the existing raid loot csv builder to remain available")
    assertContains({ raidCsv }, "LootNID,ItemID,ItemName", "expected existing raid csv to keep loot columns")
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

    h.Core.GetCurrentRaid = function()
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
    h.addon.Comms.Sync = function(prefix, payload)
        groupMessages[#groupMessages + 1] = {
            prefix = prefix,
            payload = payload,
        }
    end

    h:load("!KRT/Core/DBSyncer.lua")
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
    local syncPrefix = table.concat({ "RQ", "1", "2", "SYNC", "77", "Naxxramas", "25", "4" }, "\t")
    assertEqual(groupMessages[1].payload:sub(1, #syncPrefix), syncPrefix, "expected sync payload header to stay stable")
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
                { playerNid = 1, name = "Alice", rank = 1, subgroup = 2, class = "MAGE", join = 1000, count = 3 },
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

    source:load("!KRT/Modules/Base64.lua")
    source:load("!KRT/Core/DBSyncer.lua")
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
    pushTarget:load("!KRT/Modules/Base64.lua")
    pushTarget:load("!KRT/Core/DBSyncer.lua")

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
    assertEqual(_G.KRT_Raids[1].changes.Alice, "Fire", "expected imported push snapshot to preserve changes")

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
    syncTarget.Core.GetCurrentRaid = function()
        return 1
    end
    syncTarget.addon.IsInGroup = function()
        return true
    end
    syncTarget.addon.IsInRaid = function()
        return false
    end
    syncTarget:load("!KRT/Modules/Base64.lua")
    syncTarget:load("!KRT/Core/DBSyncer.lua")

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
    assertEqual(mergedRaid.changes.Alice, "Fire", "expected requested sync to merge changes")
    assertTrue(syncTarget.addon.DB.Syncer._pendingRequests[syncRequestId] == nil, "expected successful sync merge to complete the pending request")
end)

test("logger updates duplicate item entries by lootNid only", function()
    local h = newHarness()
    local link = h.registerItem(9001, "Twinblade")
    h:installRaidStore({
        {
            schemaVersion = 1,
            raidNid = 1,
            players = {
                { playerNid = 1, name = "Alice", count = 0 },
                { playerNid = 2, name = "Bob", count = 0 },
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
        return 10
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")
    h:load("!KRT/Controllers/Logger.lua")

    local Logger = h.addon.Controllers.Logger
    local raid = h.Core.EnsureRaidById(1)

    local ok = Logger.Loot:SetLootEntry(102, "Alice", h.rollTypes.OFFSPEC, 22, "TEST_DUPLICATE", 1)
    assertTrue(ok == true, "expected loot log update to succeed")
    assertEqual(raid.loot[1].looterNid, 1, "expected first duplicate entry to remain untouched")
    assertEqual(raid.loot[1].rollValue, 80, "expected first duplicate roll to remain untouched")
    assertEqual(raid.loot[2].looterNid, 1, "expected second duplicate entry to be updated")
    assertEqual(raid.loot[2].rollType, h.rollTypes.OFFSPEC, "expected second duplicate roll type to update")
    assertEqual(raid.loot[2].rollValue, 22, "expected second duplicate roll value to update")

    h.logs.error = {}
    local bad = Logger.Loot:SetLootEntry(9001, "Bob", h.rollTypes.FREE, 1, "TEST_RAW_ITEM_ID", 1)
    assertTrue(bad == false, "expected raw itemId logger update to fail")
    assertContains(h.logs.error, "expected lootNid but got raw itemId", "expected explicit raw itemId guard-rail log")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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
    local Logger = h.addon.Controllers.Logger
    local lootNid = Raid:LogTradeOnlyLoot(link, "Alice", h.rollTypes.MAINSPEC, 98, 1, "TRADE_ONLY_TEST", 1, 10, "roll-session-1")
    assertTrue((tonumber(lootNid) or 0) > 0, "expected trade-only path to create a lootNid")
    assertEqual(Raid:GetLootNidByRollSessionId("roll-session-1", 1, "Alice", 10), lootNid, "expected rollSessionId lookup to resolve trade-only loot")

    local ok = Logger.Loot:SetLootEntry(lootNid, "Alice", h.rollTypes.RESERVED, 77, "TEST_TRADE_ONLY", 1)
    assertTrue(ok == true, "expected logger update to reuse trade-only lootNid")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(raid.loot[1].lootNid, lootNid, "expected trade-only entry to keep its lootNid")
    assertEqual(raid.loot[1].rollType, h.rollTypes.RESERVED, "expected logger update to mutate same entry")
    assertEqual(raid.loot[1].rollValue, 77, "expected logger update to keep same entry")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.SetLastBoss(nil)

    Raid:AddLoot("loot-receive-self")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected event-context recovery to reuse the boss kill instead of creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 1, "expected loot logging to attach to the boss carried by the event context")
    assertEqual(h.Core.GetLastBoss(), 1, "expected event-context recovery to restore lastBoss after an explicit clear")
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
    h.Core.SetLastBoss(nil)
    Raid:AddLoot("loot-receive-self")

    local raid = h.Core.EnsureRaidById(1)
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.SetLastBoss(nil)
    Raid:AddLoot("loot-receive-second")

    local raid = h.Core.EnsureRaidById(1)
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

    local raid = h.Core.EnsureRaidById(1)
    assertTrue((tonumber(lootNid) or 0) > 0, "expected the trade-only path to create a loot entry")
    assertEqual(#raid.loot, 1, "expected the trade-only path to create one loot entry")
    assertEqual(raid.loot[1].bossNid, 1, "expected the trade-only path to reuse the session boss context")
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
    h.Core.SetLastBoss(nil)
    Raid:AddLoot("trash-loot-one")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected trash loot in the middle to be recorded")
    assertEqual(raid.loot[1].bossNid, 2, "expected the interleaved trash loot to use TrashMob")

    Raid:ClearLootWindowBossContext()
    currentTime = 1025
    h.feature.raidState.bossEventContext = nil
    h.Core.SetLastBoss(nil)
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

    local raid = h.Core.EnsureRaidById(1)
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(raid.loot[1].lootSource.kind, "trash", "expected trash loot rows to persist the trash source kind")
    assertEqual(raid.loot[1].lootSource.bossNid, 1, "expected trash loot rows to bind lootSource to the TrashMob boss bucket")
    assertEqual(raid.loot[1].lootSource.sourceNpcId, 15989, "expected trash loot rows to keep the source npc id")
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
    h.Core.SetLastBoss(nil)
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected no TrashMob fallback for a boss corpse open")
    assertEqual(raid.loot[1].bossNid, 1, "expected the loot to stay attached to Grand Widow Faerlina")
end)

test("loot window dead raid target boss creates boss context without event recovery", function()
    local h = newHarness()
    local bossLink = h.registerItem(91702, "Raid Target Faerlina Mantle")
    local bossKey = h.addon.Item.GetItemStringFromLink(bossLink)
    local currentTime = 1000
    local bossNpcId = 15953
    local bossGuid = "Creature-0-0-0-0-15953-0000000000"

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
    h.Core.SetLastBoss(nil)
    h.feature.lootState.opened = true

    assertEqual(
        Raid:_EnsureLootWindowItemContext(1, {
            { itemKey = bossKey, count = 1 },
        }, {
            ttlSeconds = 60,
            source = "LOOT_OPENED",
        }),
        1,
        "expected dead raid target boss fallback to create a boss context"
    )

    local source = Raid:GetActiveLootSource(1)
    assertTrue(source ~= nil, "expected an active boss loot source after raid target fallback")
    assertEqual(source.kind, "boss", "expected raid target fallback to classify the source as boss")
    assertEqual(source.bossNid, 1, "expected raid target fallback to bind the new boss nid")
    assertEqual(source.sourceNpcId, bossNpcId, "expected raid target fallback to preserve the boss npc id")
    assertEqual(source.sourceName, "Grand Widow Faerlina", "expected raid target fallback to preserve the boss name")

    Raid:AddLoot("raid-target-boss-loot-self")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected raid target fallback to create one boss kill")
    assertEqual(raid.bossKills[1].name, "Grand Widow Faerlina", "expected the fallback boss kill to use the boss name")
    assertEqual(raid.bossKills[1].sourceNpcId, bossNpcId, "expected the fallback boss kill to preserve the source npc id")
    assertEqual(#raid.loot, 1, "expected raid target boss loot to log one row")
    assertEqual(raid.loot[1].bossNid, 1, "expected raid target boss loot to bind to the fallback boss")
    assertEqual(raid.loot[1].lootSource.kind, "boss", "expected raid target boss loot to persist boss source metadata")
    assertEqual(raid.loot[1].lootSource.sourceNpcId, bossNpcId, "expected loot source metadata to keep the boss npc id")
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected object-source loot to log one row")
    assertEqual(raid.loot[1].lootSource.kind, "object", "expected object-source loot rows to persist the object kind")
    assertEqual(raid.loot[1].lootSource.bossNid, 0, "expected object-source loot rows to keep an unresolved lootSource boss nid")
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected loot logging to fall back to TrashMob when no scoped boss context exists")
    assertEqual(raid.bossKills[1].name, "_TrashMob_", "expected target heuristic recovery to stay disabled")
    assertEqual(raid.loot[1].bossNid, 1, "expected loot without scoped context to attach to TrashMob")
end)

test("group loot sessions keep boss association without relying on lastBoss", function()
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
    h.Core.SetLastBoss(nil)

    assertEqual(Raid:AddGroupLootMessage("greed-win-self"), "winner", "expected passive winner message to be recognized")
    Raid:AddLoot("greed-win-self")

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.bossKills, 1, "expected scoped session association to avoid creating TrashMob")
    assertEqual(raid.loot[1].bossNid, 10, "expected scoped session association to preserve original boss context")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected self winner message to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.GREED, "expected self winner message to classify the loot as GR")
    assertEqual(raid.loot[1].rollValue, 88, "expected self winner message to preserve the greed roll value")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected backfill flow to keep a single loot entry")
    assertEqual(raid.loot[1].rollValue, 96, "expected late self roll line to backfill the missing roll value")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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

    local ok = ctx.Master:BtnAward()

    assertTrue(ok == true, "expected award flow to succeed when the live loot slot link differs but the itemId matches")
    assertEqual(#ctx.givenLoot, 1, "expected award flow to reach GiveMasterLoot once")
    assertEqual(ctx.givenLoot[1].itemIndex, 1, "expected itemId fallback to resolve the first loot slot")
    assertEqual(ctx.givenLoot[1].candidateIndex, 1, "expected award flow to resolve the candidate index for the winner")
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.addon.Core.SetCurrentRaid(1)
    h.addon.Services.Raid = {
        CanObservePassiveLoot = function()
            return true
        end,
    }
    h.addon.Services.Loot = {
        AddGroupLootMessage = function(_, msg)
            if msg == "winner-loot" or msg == "winner-system" then
                return "winner"
            end
            return nil
        end,
        AddLoot = function(_, msg)
            addLootCalls[#addLootCalls + 1] = msg
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
    assertEqual(addLootCalls[1], "winner-loot", "expected loot winner messages to materialize immediately")
    assertEqual(addLootCalls[2], "winner-system", "expected system winner messages to materialize immediately")
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
    h.addon.Core.SetCurrentRaid(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
    assertEqual(#raid.loot, 1, "expected master loot receipt to create one loot entry")
    assertEqual(raid.loot[1].rollType, h.rollTypes.OFFSPEC, "expected master loot receipt to use the pending award from the active roll session")
    assertEqual(raid.loot[1].rollValue, 12, "expected master loot receipt to keep the active roll session rollValue")
    assertEqual(raid.loot[1].rollSessionId, "RS:new", "expected master loot receipt to bind the active roll session id")
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

    h.Core.GetCurrentRaid = function()
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h.Core.GetLastBoss = function()
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

    local raid = h.Core.EnsureRaidById(1)
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
                { playerNid = 1, name = "Tester", count = 0 },
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
    h.Core.GetCurrentRaid = function()
        return 1
    end

    h:load("!KRT/Services/Raid.lua")
    local Raid = h.addon.Services.Raid
    local raid = h.Core.EnsureRaidById(1)

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
                { playerNid = 1, name = "Alice", count = 0 },
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
    h.Core.GetCurrentRaid = function()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)
    Rolls:FetchRolls()

    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected Rolls service to stop owning prefilled single-award multiselect state")
    assertEqual(h.feature.lootState.winner, nil, "expected Rolls service to stop mutating the selected winner mirror directly")
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:RecordRolls(false)

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    local model = Rolls:FetchRolls()
    local first = model and model.rows and model.rows[1]

    assertTrue(eligibility ~= nil and eligibility.ok == true, "expected accepted winner to remain candidate-eligible after consuming the quota")
    assertTrue(eligibility.canSubmit ~= true, "expected accepted winner to be blocked from submitting another roll")
    assertTrue(model ~= nil and model.resolution and model.resolution.autoWinners[1] ~= nil, "expected the accepted winner to remain in the resolver output")
    assertEqual(model.resolution.autoWinners[1].name, "Alice", "expected the accepted winner to remain auto-selected after countdown finalization")
    assertTrue(first ~= nil, "expected an eligible winner row in the display model")
    assertEqual(first.status, "ROLL", "expected recorded response to stay in ROLL status")
    assertTrue(first.isEligible == true, "expected recorded response to stay eligible in the UI model")
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    assertTrue(Rolls:StartCountdown(5) == true, "expected countdown to start")
    h:flushTimers()

    local ok, reason = Rolls:SubmitDebugRoll("Alice", 87)
    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    Rolls:RecordRolls(true)
    assertTrue(Rolls:StartCountdown(5) == true, "expected countdown to start")
    h:flushTimers()

    local okAlice, reasonAlice = Rolls:SubmitDebugRoll("Alice", 96)
    local okBob, reasonBob = Rolls:SubmitDebugRoll("Bob", 96)
    local model = Rolls:FetchRolls()
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
    local changesState = raid:GetCapabilityState("changes_broadcast")

    assertEqual(lootState.allowed, false, "expected loot capability to require master looter in raid")
    assertEqual(lootState.reason, "missing_master_looter", "expected missing ML denial reason")
    assertEqual(changesState.allowed, false, "expected changes broadcast to require raid leadership")
    assertEqual(changesState.reason, "missing_leadership", "expected leadership denial reason")
    assertTrue(raid:EnsureMasterOnlyAccess() ~= true, "expected shared master-only guard to block when loot access is denied")
    assertContains(h.logs.warn, "L.WarnMLOnlyMode", "expected guard denial to use the shared warning")

    h:setRaidRoleState({
        inRaid = true,
        rank = 1,
        isMasterLooter = true,
    })

    assertTrue(raid:CanUseCapability("loot") == true, "expected ML ownership to re-enable loot capability")
    assertTrue(raid:CanUseCapability("changes_broadcast") == true, "expected raid leadership to re-enable changes broadcast")
    assertTrue(raid:CanUseCapability("ready_check") == true, "expected leadership to re-enable ready checks")
end)

test("master roll intake reopens after announcing rolls with service-owned session bootstrap", function()
    local h = newHarness()
    local link = h.registerItem(9321, "Countdownblade")

    h.addon.options.countdownDuration = 5
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")
    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    local frame = h.makeFrame(true, "KRTMaster")
    _G.KRTMasterItemCount = h.makeFrame(true, "KRTMasterItemCount")
    Master.RequestRefresh = function() end
    Master:OnLoad(frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.fromInventory = false

    Master:BtnMS()

    assertEqual(h.feature.lootState.rollStarted, true, "expected MS announce to reopen the roll-started state")
    assertEqual(h.timerCount(), 0, "expected no countdown timer before clicking the countdown button")

    Master:BtnCountdown(nil, "LeftButton")

    assertEqual(h.timerCount(), 2, "expected countdown click to schedule ticker and end timer")
end)

test("master assignment buttons stay disabled until a target is selected", function()
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
    h:load("!KRT/Modules/UI/MultiSelect.lua")
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Controllers/Master.lua")

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
    Master:OnLoad(frame)

    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.fromInventory = false
    h.feature.lootState.holder = nil
    h.feature.lootState.banker = nil
    h.feature.lootState.disenchanter = nil

    Master:Refresh()

    assertEqual(_G.KRTMasterHoldBtn._enabled, false, "expected Hold to disable when no holder is selected")
    assertEqual(_G.KRTMasterBankBtn._enabled, false, "expected Bank to disable when no banker is selected")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, false, "expected Disenchant to disable when no disenchanter is selected")

    h.feature.lootState.holder = "Alice"
    h.feature.lootState.banker = "Bob"
    h.feature.lootState.disenchanter = nil

    Master:Refresh()

    assertEqual(_G.KRTMasterHoldBtn._enabled, true, "expected Hold to enable when a holder is selected")
    assertEqual(_G.KRTMasterBankBtn._enabled, true, "expected Bank to enable when a banker is selected")
    assertEqual(_G.KRTMasterDisenchantBtn._enabled, false, "expected Disenchant to stay disabled without a target")
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

    h.Core.GetRaidStoreOrNil = function()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Controllers/Master.lua")

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
    Master:OnLoad(frame)
    Master:Refresh()

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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Controllers/Master.lua")

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
    Master:OnLoad(frame)
    Master:Refresh()

    local itemCountBox = _G.KRTMasterItemCount
    assertTrue(type(itemCountBox.OnTextChanged) == "function", "expected OnTextChanged to be bound through Frames.BindEditBoxHandlers")
    assertTrue(type(itemCountBox.OnEnterPressed) == "function", "expected OnEnterPressed to be bound through Frames.BindEditBoxHandlers")
    assertTrue(type(itemCountBox.OnEditFocusLost) == "function", "expected OnEditFocusLost to be bound through Frames.BindEditBoxHandlers")

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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Controllers/Master.lua")

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
    Master:OnLoad(frame)
    Master.EnsureUI = function()
        return frame
    end
    Master:LOOT_OPENED()
    Master:BtnSelectItem(h.makeFrame(true, "ItemSelectInvoker"))

    local firstButton = _G.KRTMasterItemSelectionBtn1
    local secondButton = _G.KRTMasterItemSelectionBtn2

    assertTrue(firstButton ~= nil, "expected the selection popup to create the first selection button")
    assertTrue(secondButton ~= nil, "expected the selection popup to create the second selection button")
    assertTrue(type(firstButton.OnClick) == "function", "expected the created selection button to keep its click handler")

    firstButton:OnClick("LeftButton")

    assertEqual(selectedIndex, 1, "expected clicking the selection popup button to pick the corresponding loot index")
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
        RollStatus = function()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Modules/UI/ListController.lua")
    h.feature.ListController = h.addon.ListController
    h:load("!KRT/Controllers/Master.lua")

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
    Master:OnLoad(frame)
    Master:Refresh()

    local row = _G.KRTMasterPlayerBtn1
    assertTrue(row ~= nil, "expected the shared list controller to create the first roll row")
    assertEqual(row.playerName, "Alice", "expected the created roll row to keep the player identity for click handling")
    assertTrue(type(row.OnClick) == "function", "expected the created roll row to keep an OnClick handler")

    row:OnClick()

    assertTrue(h.addon.MultiSelect.MultiSelectIsSelected("MLRollWinners", "Alice"), "expected clicking the rendered row to select the winner")
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    assertTrue(Rolls:SetManualExclusion("Alice", true) == true, "expected manual exclusion API to accept a valid player name")

    local eligibility = Rolls:GetCandidateEligibility("Alice", link, h.rollTypes.MAINSPEC)
    assertTrue(eligibility ~= nil and eligibility.ok ~= true, "expected manually excluded player to fail candidate eligibility")
    assertEqual(eligibility.reason, "manual_exclusion", "expected manual exclusion to surface through the eligibility reason")

    Rolls:RecordRolls(true)
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected pass to be accepted while the session is open")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 88) == true, "expected pass responses to remain reversible into a valid roll")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:PlayerPass("Alice") == true, "expected explicit pass to be accepted during an open roll")
    Rolls:RecordRolls(false)

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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    assertTrue(Rolls:PlayerCancel("Alice") == true, "expected cancel to retract an earlier explicit roll response")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    assertTrue(Rolls:SubmitDebugRoll("Alice", 98) == true, "expected the initial roll to be accepted")
    assertTrue(Rolls:PlayerCancel("Alice") == true, "expected cancel to retract the current roll response")
    assertTrue(Rolls:SubmitDebugRoll("Alice", 91) == true, "expected cancelled responses to remain reversible into a valid roll")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.RESERVED

    Rolls:RecordRolls(true)
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 98")
    Rolls:CHAT_MSG_SYSTEM("Cara 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    assertTrue(model.resolution.requiresManualResolution == true, "expected a first-place tie to require manual resolution before reroll")
    assertTrue(Rolls:BeginTieReroll(model.resolution.tiedNames) == true, "expected tied winners to reopen the current session as a reroll")

    model = Rolls:FetchRolls()
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

test("master award button triggers reroll for single-select ties", function()
    local h = newHarness()
    local link = h.registerItem(9308, "Mastertieblade")
    local rerollNames
    local refreshCount = 0

    h.addon.Services.Loot = {
        GetItem = function()
            return { itemLink = link }
        end,
        GetItemLink = function()
            return link
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
        HighestRoll = function()
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
    h:load("!KRT/Controllers/Master.lua")

    local Master = h.addon.Controllers.Master
    Master.RequestRefresh = function()
        refreshCount = refreshCount + 1
    end

    h.feature.lootState.lootCount = 1
    h.feature.lootState.rollsCount = 2
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = false

    assertTrue(Master:BtnAward() == true, "expected single-select tie to trigger a reroll flow")
    assertEqual(rerollNames[1], "Alice", "expected tie reroll to receive the tied players in order")
    assertEqual(rerollNames[2], "Bob", "expected tie reroll to receive the tied players in order")
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

    local ok = ctx.Master:BtnAward()

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

    local ok = ctx.Master:BtnAward()

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

    local ok = ctx.Master:BtnAward()

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

    local ok = ctx.Master:BtnAward()

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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.addon.options.showLootCounterDuringMSRoll = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:RecordRolls(false)

    playerInRaid = false
    local model = Rolls:FetchRolls()
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 1
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    local first = model and model.rows and model.rows[1]

    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected inventory flow to keep the winner outside the loot-window multiselect")
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
    h.feature.MultiSelect = h.addon.MultiSelect
    h:load("!KRT/Services/Rolls/Service.lua")

    local Rolls = h.addon.Services.Rolls
    h.feature.lootState.lootCount = 1
    h.feature.lootState.selectedItemCount = 2
    h.feature.lootState.currentRollType = h.rollTypes.MAINSPEC
    h.feature.lootState.fromInventory = true

    Rolls:RecordRolls(true)
    Rolls:CHAT_MSG_SYSTEM("Alice 98")
    Rolls:CHAT_MSG_SYSTEM("Bob 77")
    Rolls:CHAT_MSG_SYSTEM("Cara 45")
    Rolls:RecordRolls(false)

    local model = Rolls:FetchRolls()
    assertEqual(h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 0, "expected Rolls service to stop prefiling inventory multi-copy multiselect state")
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

    assertTrue(ctx.Master:BtnAward() == true, "expected self-keep trade step to complete")
    assertEqual(#ctx.initiatedTrades, 0, "expected self-keep to avoid opening a trade window")
    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected self-keep to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Alice", "expected self-keep to advance to the next selected winner")
    assertEqual(ctx.h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 1, "expected self-keep to remove the completed winner from multiselect")
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

    assertTrue(ctx.Master:BtnAward() == true, "expected trade step to be accepted")
    assertEqual(#ctx.initiatedTrades, 1, "expected non-trader winner to open a trade")
    assertEqual(ctx.initiatedTrades[1], "Alice", "expected the first selected non-trader winner to receive the trade")
    assertEqual(ctx.h.feature.lootState.itemTraded, nil, "expected trade progress to wait for TRADE_ACCEPT_UPDATE before consuming")

    ctx.bagItems[0][1] = nil
    ctx.Master:TRADE_ACCEPT_UPDATE(1, 1)

    assertEqual(ctx.h.feature.lootState.itemTraded, 1, "expected trade completion to consume exactly one inventory copy")
    assertEqual(ctx.h.feature.lootState.winner, "Tester", "expected trade completion to advance to the remaining selected winner")
    assertEqual(ctx.h.addon.MultiSelect.MultiSelectCount("MLRollWinners"), 1, "expected trade completion to remove the completed winner from multiselect")
    assertEqual(#ctx.addCounts, 1, "expected one LootCounter increment after trade completion")
    assertEqual(ctx.addCounts[1].name, "Alice", "expected trade completion to credit the traded winner")
    assertEqual(ctx.addCounts[1].count, 1, "expected trade completion to credit exactly one awarded item")
    assertEqual(#ctx.loggerRequests, 1, "expected one logger update after trade acceptance")
    assertEqual(ctx.loggerRequests[1].looter, "Alice", "expected trade completion logger update to use the traded winner")
    assertEqual(ctx.loggerRequests[1].source, "TRADE_ACCEPT", "expected trade completion logger update to use the accept source")
    assertEqual(ctx.getClearLootCount(), 0, "expected multi-step trade completion to preserve the current item until all winners are done")
end)

test("logger export tab stays disabled while the export workflow is staged off", function()
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
    h.Core.GetCurrentRaid = function()
        return 1
    end
    h:load("!KRT/Services/Logger/Store.lua")
    h:load("!KRT/Services/Logger/View.lua")
    h:load("!KRT/Services/Logger/Helpers.lua")
    h:load("!KRT/Services/Logger/Actions.lua")
    h:load("!KRT/Controllers/Logger.lua")

    local Logger = h.addon.Controllers.Logger
    local buildCount = 0
    Logger.View.BuildRaidCsv = function(_, _, raidId)
        buildCount = buildCount + 1
        return "csv:" .. tostring(raidId)
    end

    local loggerFrame = h.makeFrame(true, "KRTLogger")
    local historyFrame = h.makeFrame(true, "KRTLoggerHistory")
    local exportFrame = h.makeFrame(false, "KRTLoggerExport")
    local bossBox = h.makeFrame(true, "KRTLoggerBossBox")
    local attendeesBox = h.makeFrame(true, "KRTLoggerAttendeesBox")
    local scrollFrame = h.makeFrame(true, "KRTLoggerExportCsvScrollFrame")
    scrollFrame.ScrollBar = h.makeFrame(true, "KRTLoggerExportCsvScrollFrameScrollBar")
    scrollFrame.ScrollBar.GetWidth = function()
        return 16
    end
    local csvText = h.makeFrame(true, "KRTLoggerExportCsvText")

    Logger.frame = loggerFrame
    Logger.selectedRaid = 1
    Logger.activeTab = "history"
    Logger.refs = {
        history = historyFrame,
        export = exportFrame,
        bossBox = bossBox,
        attendeesBox = attendeesBox,
        exportCsvText = csvText,
        exportCsvScrollFrame = scrollFrame,
    }

    h.Bus.TriggerEvent(h.addon.Events.Internal.LoggerSelectRaid, 1)
    assertEqual(buildCount, 0, "expected hidden export to skip csv rebuild")
    assertTrue(Logger.Export._csvDirty == true, "expected hidden export to remain dirty")

    Logger:SetTab("export")
    h.flushTimers()
    assertEqual(Logger.activeTab, "history", "expected export tab requests to stay normalized to history")
    assertEqual(buildCount, 0, "expected disabled export tab to skip csv rebuild")
    assertTrue(exportFrame:IsShown() ~= true, "expected export panel to stay hidden while the tab is disabled")
    assertTrue(Logger.Export._csvDirty == true, "expected disabled export tab to leave csv state dirty")

    Logger:SetTab("history")
    h.Bus.TriggerEvent(h.addon.Events.Internal.RaidLootUpdate, 1)
    assertEqual(buildCount, 0, "expected hidden export updates to stay lazy")
    assertTrue(Logger.Export._csvDirty == true, "expected hidden export changes to mark csv dirty")

    Logger:SetTab("export")
    h.flushTimers()
    assertEqual(Logger.activeTab, "history", "expected repeated export tab requests to keep the tab disabled")
    assertEqual(buildCount, 0, "expected disabled export tab to keep csv rebuilds deferred")
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
    h.Core.GetCurrentRaid = function()
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
