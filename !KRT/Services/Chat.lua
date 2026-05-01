-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local C = feature.C
local Strings = feature.Strings
local Comms = feature.Comms
local Services = feature.Services

local find = string.find
local len = string.len
local upper = string.upper
local tinsert = table.insert
local tconcat = table.concat
local tostring = tostring
local tonumber = tonumber
local type = type
local ipairs = ipairs

-- =========== Chat Output Helpers  =========== --
do
    feature.EnsureServiceNamespace("Chat")
    local module = addon.Services.Chat

    -- Timer ownership: ticker for controlled LFM spammer output.
    addon.Timer.BindMixin(module, "Chat")

    -- ----- Internal state ----- --
    local chatOutputFormat = C.CHAT_OUTPUT_FORMAT
    local chatPrefixShort = C.CHAT_PREFIX_SHORT
    local chatPrefixHex = C.CHAT_PREFIX_HEX
    local DEFAULT_SPAM_DURATION_SECONDS = 60
    local DEFAULT_SPAM_OUTPUT = "LFM"
    local MAX_SPAM_RUNTIME_SECONDS = 1800
    local MAX_SPAM_MESSAGES_PER_RUN = 30

    local spamRuntime = {
        ticking = false,
        paused = false,
        countdownRemaining = 0,
        runElapsedSeconds = 0,
        messagesSent = 0,
        durationSeconds = DEFAULT_SPAM_DURATION_SECONDS,
        output = DEFAULT_SPAM_OUTPUT,
        channels = {},
        ticker = nil,
        onTick = nil,
        onAutoStop = nil,
        sendFn = nil,
    }

    -- ----- Private helpers ----- --
    local function isCountdownMessage(text)
        local seconds = addon.Deformat(text, L.ChatCountdownTic)
        return (seconds ~= nil) or (find(text, L.ChatCountdownEnd) ~= nil)
    end

    local function canUseRaidWarning()
        local raidService = Services.Raid
        if raidService and type(raidService.CanUseCapability) == "function" then
            return raidService:CanUseCapability("raid_warning")
        end

        local leaderFn = addon.UnitIsGroupLeader or feature.UnitIsGroupLeader
        local assistantFn = addon.UnitIsGroupAssistant or feature.UnitIsGroupAssistant
        return (leaderFn and leaderFn("player")) or (assistantFn and assistantFn("player")) or false
    end

    local function resolveGroupType()
        if type(addon.GetGroupTypeAndCount) == "function" then
            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" or groupType == "party" then
                return groupType
            end
        end

        if type(addon.IsInRaid) == "function" and addon.IsInRaid() then
            return "raid"
        end
        if type(IsInRaid) == "function" and IsInRaid() then
            return "raid"
        end
        if type(UnitInRaid) == "function" and UnitInRaid("player") then
            return "raid"
        end

        local raidCount = (GetRealNumRaidMembers and GetRealNumRaidMembers()) or (GetNumRaidMembers and GetNumRaidMembers()) or 0
        if (tonumber(raidCount) or 0) > 0 then
            return "raid"
        end

        local partyCount = (GetRealNumPartyMembers and GetRealNumPartyMembers()) or (GetNumPartyMembers and GetNumPartyMembers()) or 0
        if (tonumber(partyCount) or 0) > 0 then
            return "party"
        end

        return nil
    end

    local function resolveAnnounceChannel(text, preferredChannel)
        if preferredChannel then
            return preferredChannel
        end

        local groupType = resolveGroupType()
        if groupType == "raid" then
            local options = addon.options or {}
            if isCountdownMessage(text) and options.countdownSimpleRaidMsg then
                return "RAID"
            end
            if options.useRaidWarning and canUseRaidWarning() then
                return "RAID_WARNING"
            end
            return "RAID"
        end
        if groupType == "party" then
            return "PARTY"
        end
        return nil
    end

    local function cloneChannels(channels)
        if type(channels) ~= "table" then
            return {}
        end

        local copy = {}
        for i = 1, #channels do
            copy[#copy + 1] = channels[i]
        end
        return copy
    end

    local function cancelSpamTicker()
        if spamRuntime.ticker then
            module:CancelTimer(spamRuntime.ticker)
            spamRuntime.ticker = nil
        end
    end

    local function getSpamRuntimeSnapshot()
        return {
            ticking = spamRuntime.ticking,
            paused = spamRuntime.paused,
            countdownRemaining = spamRuntime.countdownRemaining,
            runElapsedSeconds = spamRuntime.runElapsedSeconds,
            messagesSent = spamRuntime.messagesSent,
            durationSeconds = spamRuntime.durationSeconds,
            output = spamRuntime.output,
            channels = cloneChannels(spamRuntime.channels),
        }
    end

    local function fireSpamTick()
        local onTick = spamRuntime.onTick
        if type(onTick) == "function" then
            onTick(getSpamRuntimeSnapshot())
        end
    end

    local function finalizeAutoStop(reason)
        local onAutoStop = spamRuntime.onAutoStop
        module:StopSpamCycle(true, true)
        if type(onAutoStop) == "function" then
            onAutoStop(reason, getSpamRuntimeSnapshot())
        end
    end

    local function runSpamTick()
        if not spamRuntime.ticking or spamRuntime.paused then
            return
        end

        spamRuntime.runElapsedSeconds = spamRuntime.runElapsedSeconds + 1
        if spamRuntime.runElapsedSeconds >= MAX_SPAM_RUNTIME_SECONDS then
            addon:warn(L.MsgSpammerAutoStopDuration:format(MAX_SPAM_RUNTIME_SECONDS))
            finalizeAutoStop("duration_limit")
            return
        end

        spamRuntime.countdownRemaining = spamRuntime.countdownRemaining - 1
        if spamRuntime.countdownRemaining <= 0 then
            local sendFn = spamRuntime.sendFn
            local ok
            if type(sendFn) == "function" then
                ok = sendFn(spamRuntime.output, spamRuntime.channels)
            else
                ok = module:SendSpamOutput(spamRuntime.output, spamRuntime.channels)
            end

            if ok == false then
                finalizeAutoStop("send_failed")
                return
            end

            spamRuntime.messagesSent = spamRuntime.messagesSent + 1
            if spamRuntime.messagesSent >= MAX_SPAM_MESSAGES_PER_RUN then
                addon:warn(L.MsgSpammerAutoStopMessages:format(MAX_SPAM_MESSAGES_PER_RUN))
                finalizeAutoStop("message_limit")
                return
            end

            spamRuntime.countdownRemaining = module:NormalizeSpamDuration(spamRuntime.durationSeconds)
        end

        fireSpamTick()
    end

    -- ----- Public methods ----- --
    function module:Print(text, prefix)
        local msg = Strings.FormatChatMessage(text, prefix or chatPrefixShort, chatOutputFormat, chatPrefixHex)
        addon:info("%s", msg)
    end

    function module:Announce(text, channel)
        local msg = tostring(text)
        local selectedChannel = resolveAnnounceChannel(msg, channel)
        if not selectedChannel or selectedChannel == "" then
            return module:Print(msg)
        end
        Comms.Chat(msg, selectedChannel)
    end

    function module:ShowMasterOnlyWarning()
        addon:warn(L.WarnMLOnlyMode or L.WarnMLNoPermission)
    end

    function module:NormalizeWarningMessage(content)
        if type(content) ~= "string" then
            return nil
        end

        local message = Strings.TrimText(content)
        if message == "" then
            return nil
        end
        return message
    end

    function module:AnnounceWarningMessage(content)
        local message = module:NormalizeWarningMessage(content)
        if not message then
            return false, "empty"
        end

        if addon.IsInRaid and addon.IsInRaid() and addon.options and addon.options.useRaidWarning then
            local raidService = Services.Raid
            if raidService and type(raidService.CanUseCapability) == "function" and not raidService:CanUseCapability("raid_warning") then
                addon:warn(L.WarnRaidWarningFallback)
            end
        end

        module:Announce(message)
        return true
    end

    function module:NormalizeSpamDuration(durationValue, fallbackValue)
        local durationSeconds = tonumber(durationValue)
        if not durationSeconds or durationSeconds <= 0 then
            durationSeconds = tonumber(fallbackValue)
        end
        if not durationSeconds or durationSeconds <= 0 then
            durationSeconds = DEFAULT_SPAM_DURATION_SECONDS
        end
        return math.floor(durationSeconds)
    end

    function module:BuildSpammerOutput(state, defaultOutput)
        local baseOutput = defaultOutput or DEFAULT_SPAM_OUTPUT
        local source = (type(state) == "table") and state or {}
        local outBuf = { baseOutput }

        local name = source.name or ""
        if name ~= "" then
            tinsert(outBuf, " ")
            tinsert(outBuf, name)
        end

        local needParts = {}
        local function addNeed(count, label, class)
            count = tonumber(count) or 0
            if count <= 0 then
                return
            end

            local text = count .. " " .. label
            if class and class ~= "" then
                text = text .. " (" .. class .. ")"
            end
            needParts[#needParts + 1] = text
        end

        addNeed(source.tank, L.StrTank, source.tankClass)
        addNeed(source.healer, L.StrHealer, source.healerClass)
        addNeed(source.melee, L.StrMelee, source.meleeClass)
        addNeed(source.ranged, L.StrRanged, source.rangedClass)

        if #needParts > 0 then
            tinsert(outBuf, " - ")
            tinsert(outBuf, L.StrSpammerNeedStr)
            tinsert(outBuf, " ")
            tinsert(outBuf, tconcat(needParts, ", "))
        end

        if source.message and source.message ~= "" then
            tinsert(outBuf, " - ")
            tinsert(outBuf, Strings.FindAchievement(source.message))
        end

        local output = tconcat(outBuf)
        if output == baseOutput then
            return output
        end

        local total = (tonumber(source.tank) or 0) + (tonumber(source.healer) or 0) + (tonumber(source.melee) or 0) + (tonumber(source.ranged) or 0)

        local is25 = (name ~= "" and name:match("%f[%d]25%f[%D]")) ~= nil
        local maxSize = is25 and 25 or 10
        return output .. " (" .. (maxSize - total) .. "/" .. maxSize .. ")"
    end

    function module:SendSpamOutput(output, channels)
        local text = tostring(output or "")
        if len(text) > 255 then
            return false, "too_long"
        end

        local channelList = cloneChannels(channels)
        if #channelList <= 0 then
            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" then
                Comms.Chat(text, "RAID", nil, nil, true)
            elseif groupType == "party" then
                Comms.Chat(text, "PARTY", nil, nil, true)
            else
                module:Print(text)
            end
            return true
        end

        for _, channel in ipairs(channelList) do
            if type(channel) == "number" then
                Comms.Chat(text, "CHANNEL", nil, channel, true)
            else
                Comms.Chat(text, upper(channel), nil, nil, true)
            end
        end

        return true
    end

    function module:GetSpamRuntimeState()
        return getSpamRuntimeSnapshot()
    end

    function module:StartSpamCycle(config)
        config = (type(config) == "table") and config or {}

        cancelSpamTicker()

        spamRuntime.durationSeconds = module:NormalizeSpamDuration(config.duration, spamRuntime.durationSeconds)
        if config.resetRun then
            spamRuntime.runElapsedSeconds = 0
            spamRuntime.messagesSent = 0
        end

        if config.output ~= nil then
            spamRuntime.output = tostring(config.output)
        end
        if config.channels ~= nil then
            spamRuntime.channels = cloneChannels(config.channels)
        end

        spamRuntime.sendFn = (type(config.sendFn) == "function") and config.sendFn or nil
        spamRuntime.onTick = (type(config.onTick) == "function") and config.onTick or nil
        spamRuntime.onAutoStop = (type(config.onAutoStop) == "function") and config.onAutoStop or nil

        if config.resetCountdown or spamRuntime.countdownRemaining <= 0 then
            spamRuntime.countdownRemaining = spamRuntime.durationSeconds
        end

        spamRuntime.ticking = true
        spamRuntime.paused = false

        spamRuntime.ticker = module:ScheduleRepeatingTimer(runSpamTick, 1)
        fireSpamTick()

        return true, getSpamRuntimeSnapshot()
    end

    function module:StopSpamCycle(resetCountdown, resetRun)
        cancelSpamTicker()

        spamRuntime.ticking = false
        spamRuntime.paused = false

        if resetCountdown then
            spamRuntime.countdownRemaining = 0
        end
        if resetRun then
            spamRuntime.runElapsedSeconds = 0
            spamRuntime.messagesSent = 0
        end

        spamRuntime.sendFn = nil
        spamRuntime.onTick = nil
        spamRuntime.onAutoStop = nil

        return getSpamRuntimeSnapshot()
    end

    function module:PauseSpamCycle()
        if not spamRuntime.ticking or spamRuntime.paused then
            return false, getSpamRuntimeSnapshot()
        end

        spamRuntime.paused = true
        cancelSpamTicker()
        fireSpamTick()
        return true, getSpamRuntimeSnapshot()
    end
end
