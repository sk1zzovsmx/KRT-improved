-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local Frames = feature.Frames or addon.Frames
local Strings = feature.Strings or addon.Strings
local Comms = feature.Comms or addon.Comms
local Services = feature.Services or addon.Services or {}
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local pairs, ipairs, type, select = pairs, ipairs, type, select
local find, strlen = string.find, string.len
local gsub, upper = string.gsub, string.upper
local tostring, tonumber = tostring, tonumber

-- =========== LFM Spam Module  =========== --
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Spammer = addon.Controllers.Spammer or {}
    local module = addon.Controllers.Spammer
    -- ----- Internal state ----- --
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTSpammer")
    local UI = {
        Localized = false,
        Loaded = false,
    }
    -- Defaults / constants
    local DEFAULT_DURATION_STR = "60"
    local DEFAULT_DURATION_NUM = 60
    local DEFAULT_OUTPUT = "LFM"
    local MAX_SPAM_RUNTIME_SECONDS = 1800
    local MAX_SPAM_MESSAGES_PER_RUN = 30

    -- Runtime state
    local loaded = false

    -- Duration kept as string for coherence with EditBox/SV
    local duration = DEFAULT_DURATION_STR

    local finalOutput = DEFAULT_OUTPUT

    local ticking = false
    local paused = false
    local countdownTicker
    local countdownRemaining = 0
    local runElapsedSeconds = 0
    local messagesSent = 0

    local inputsLocked = false
    local previewDirty = true

    local inputFields = {
        "Name",
        "Duration",
        "Tank",
        "TankClass",
        "Healer",
        "HealerClass",
        "Melee",
        "MeleeClass",
        "Ranged",
        "RangedClass",
        "Message",
    }

    local resetFields = {
        "Name",
        "Tank",
        "TankClass",
        "Healer",
        "HealerClass",
        "Melee",
        "MeleeClass",
        "Ranged",
        "RangedClass",
        "Message",
    }

    local previewFields = {
        { key = "name", box = "Name" },
        { key = "tank", box = "Tank", number = true },
        { key = "tankClass", box = "TankClass" },
        { key = "healer", box = "Healer", number = true },
        { key = "healerClass", box = "HealerClass" },
        { key = "melee", box = "Melee", number = true },
        { key = "meleeClass", box = "MeleeClass" },
        { key = "ranged", box = "Ranged", number = true },
        { key = "rangedClass", box = "RangedClass" },
        { key = "message", box = "Message" },
    }

    local lastControls = {
        locked = nil,
        canStart = nil,
        btnLabel = nil,
        isStop = nil,
    }

    local lastState = {
        name = nil,
        tank = 0,
        tankClass = nil,
        healer = 0,
        healerClass = nil,
        melee = 0,
        meleeClass = nil,
        ranged = 0,
        rangedClass = nil,
        message = nil,
        duration = nil, -- string
    }
    -- Forward declarations
    local renderPreview
    local startSpamCycle
    local stopSpamCycle
    local updateControls
    local buildOutput
    local updateTickDisplay
    local setInputsLocked
    local getValidDuration

    -- ----- Private helpers ----- --
    function UI.AcquireRefs(frame)
        local refs = {
            clearBtn = Frames.Ref(frame, "ClearBtn"),
            startBtn = Frames.Ref(frame, "StartBtn"),
            duration = Frames.Ref(frame, "Duration"),
            healer = Frames.Ref(frame, "Healer"),
            healerClass = Frames.Ref(frame, "HealerClass"),
            melee = Frames.Ref(frame, "Melee"),
            meleeClass = Frames.Ref(frame, "MeleeClass"),
            message = Frames.Ref(frame, "Message"),
            name = Frames.Ref(frame, "Name"),
            ranged = Frames.Ref(frame, "Ranged"),
            rangedClass = Frames.Ref(frame, "RangedClass"),
            tank = Frames.Ref(frame, "Tank"),
            tankClass = Frames.Ref(frame, "TankClass"),
            chatGuild = Frames.Ref(frame, "ChatGuild"),
            chatYell = Frames.Ref(frame, "ChatYell"),
            channels = {},
        }
        for i = 1, 8 do
            refs.channels[i] = Frames.Ref(frame, "Chat" .. i)
        end
        return refs
    end

    -- Small helpers
    local function resetLastState()
        lastState.name = nil
        lastState.tank = 0
        lastState.tankClass = nil
        lastState.healer = 0
        lastState.healerClass = nil
        lastState.melee = 0
        lastState.meleeClass = nil
        lastState.ranged = 0
        lastState.rangedClass = nil
        lastState.message = nil
        lastState.duration = nil
    end

    local function setCheckbox(suffix, checked)
        local chk = _G[frameName .. suffix]
        if chk and chk.SetChecked then
            chk:SetChecked(checked and true or false)
        end
    end

    local function resetAllChannelCheckboxes()
        for i = 1, 8 do
            setCheckbox("Chat" .. i, false)
        end
        setCheckbox("ChatGuild", false)
        setCheckbox("ChatYell", false)
    end

    -- Deterministic: sync Duration immediately from UI/SV (no waiting for preview tick)
    local function syncDurationNow()
        local value
        local frame = getFrame()

        if frame and frame:IsShown() then
            local box = _G[frameName .. "Duration"]
            if box then
                value = box:GetText()
                if value == "" then
                    value = DEFAULT_DURATION_STR
                    box:SetText(value)
                end
                value = tostring(value)
            end
        end

        if not value or value == "" then
            value = (KRT_Spammer and KRT_Spammer.Duration) or DEFAULT_DURATION_STR
            value = tostring(value)
        end

        duration = value
        lastState.duration = value
        KRT_Spammer.Duration = value
    end

    -- Deterministic: ensure preview/output is computed before Start/Resume
    local function ensureReadyForStart()
        syncDurationNow()

        local frame = getFrame()
        if frame and frame:IsShown() then
            if previewDirty or not finalOutput or finalOutput == "" then
                renderPreview()
                previewDirty = false
            end
        end
    end

    local function resetLengthUI()
        local frame = getFrame()
        if not frame then
            return
        end
        local len = strlen(DEFAULT_OUTPUT)
        local lenStr = len .. "/255"

        local out = _G[frameName .. "Output"]
        if out then
            out:SetText(DEFAULT_OUTPUT)
        end

        local lengthText = _G[frameName .. "Length"]
        if lengthText then
            lengthText:SetText(lenStr)
            lengthText:SetTextColor(0.5, 0.5, 0.5)
        end

        local msg = _G[frameName .. "Message"]
        if msg and msg.SetMaxLetters then
            msg:SetMaxLetters(255)
        end
    end

    -- ----- Public methods ----- --
    -- OnLoad frame
    function module:OnLoad(frame)
        frameName = Frames.InitModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                module:RequestRefresh()
            end,
        })
        UI.Loaded = frameName ~= nil
        if not UI.Loaded then
            return
        end

        -- Localize once (not per tick)
        UI.Localize()

        if frame:IsShown() then
            module:RequestRefresh()
        end
    end

    local function BindHandlers(_, _, refs)
        Frames.SafeSetScript(refs.clearBtn, "OnClick", function()
            module:Clear()
        end)
        Frames.SafeSetScript(refs.startBtn, "OnClick", function()
            module:Start()
        end)

        Frames.SafeSetScript(refs.duration, "OnTabPressed", function()
            module:Tab("Tank", "Name")
        end)
        Frames.SafeSetScript(refs.healer, "OnTabPressed", function()
            module:Tab("HealerClass", "TankClass")
        end)
        Frames.SafeSetScript(refs.healerClass, "OnTabPressed", function()
            module:Tab("Melee", "Healer")
        end)
        Frames.SafeSetScript(refs.melee, "OnTabPressed", function()
            module:Tab("MeleeClass", "HealerClass")
        end)
        Frames.SafeSetScript(refs.meleeClass, "OnTabPressed", function()
            module:Tab("Ranged", "Melee")
        end)
        Frames.SafeSetScript(refs.message, "OnTabPressed", function()
            module:Tab("Name", "RangedClass")
        end)
        Frames.SafeSetScript(refs.name, "OnTabPressed", function()
            module:Tab("Duration", "Message")
        end)
        Frames.SafeSetScript(refs.ranged, "OnTabPressed", function()
            module:Tab("RangedClass", "MeleeClass")
        end)
        Frames.SafeSetScript(refs.rangedClass, "OnTabPressed", function()
            module:Tab("Message", "Ranged")
        end)
        Frames.SafeSetScript(refs.tank, "OnTabPressed", function()
            module:Tab("TankClass", "Duration")
        end)
        Frames.SafeSetScript(refs.tankClass, "OnTabPressed", function()
            module:Tab("Healer", "Tank")
        end)

        for i = 1, #refs.channels do
            local channelBox = refs.channels[i]
            Frames.SafeSetScript(channelBox, "OnClick", function(self, button)
                module:Save(self, button)
            end)
        end
        Frames.SafeSetScript(refs.chatGuild, "OnClick", function(self, button)
            module:Save(self, button)
        end)
        Frames.SafeSetScript(refs.chatYell, "OnClick", function(self, button)
            module:Save(self, button)
        end)
    end

    local function OnLoadFrame(frame)
        module:OnLoad(frame)
        return frameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        localize = function()
            UI.Localize()
        end,
        onLoad = OnLoadFrame,
    })

    -- Save (EditBox / Checkbox)
    function module:Save(box)
        if not box then
            return
        end

        local boxName = box:GetName()
        local target = gsub(boxName, frameName, "")

        if find(target, "Chat") then
            KRT_Spammer.Channels = KRT_Spammer.Channels or {}

            local channel = gsub(target, "Chat", "")
            local id = tonumber(channel) or select(1, GetChannelName(channel))
            channel = (id and id > 0) and id or channel

            -- FIX: GetChecked can be true/false or 1/0
            local checked = box:GetChecked()
            checked = (checked == true or checked == 1)

            local existed = tContains(KRT_Spammer.Channels, channel)
            if checked and not existed then
                tinsert(KRT_Spammer.Channels, channel)
            elseif not checked and existed then
                local i = addon.tIndexOf(KRT_Spammer.Channels, channel)
                while i do
                    tremove(KRT_Spammer.Channels, i)
                    i = addon.tIndexOf(KRT_Spammer.Channels, channel)
                end
            end
        else
            local value = Strings.TrimText(box:GetText())
            value = (value == "") and nil or value
            KRT_Spammer[target] = value
            box:ClearFocus()
        end

        loaded = false
        previewDirty = true
        module:RequestRefresh()
    end

    -- Start/Stop/Pause
    function module:Start()
        ensureReadyForStart()

        if addon.WithinRange(strlen(finalOutput), 4, 255) then
            if paused then
                paused = false
                setInputsLocked(true)
                startSpamCycle(false)
            elseif ticking then
                ticking = false
                paused = false
                stopSpamCycle(true)
                setInputsLocked(false)
            else
                ticking = true
                paused = false
                runElapsedSeconds = 0
                messagesSent = 0
                setInputsLocked(true)
                startSpamCycle(true)
            end
            module:RequestRefresh()
        end
    end

    function module:Stop()
        ticking = false
        paused = false
        runElapsedSeconds = 0
        messagesSent = 0
        stopSpamCycle(true)
        setInputsLocked(false)
        module:RequestRefresh()
    end

    function module:Pause()
        if not ticking or paused then
            return
        end
        paused = true
        stopSpamCycle(false)
        setInputsLocked(false)
        module:RequestRefresh()
    end

    -- Spam
    function module:Spam()
        if strlen(finalOutput) > 255 then
            addon:error(L.StrSpammerErrLength)
            module:Stop()
            return false
        end

        local chList = KRT_Spammer.Channels or {}

        if #chList <= 0 then
            local groupType = addon.GetGroupTypeAndCount()
            if groupType == "raid" then
                Comms.Chat(tostring(finalOutput), "RAID", nil, nil, true)
            elseif groupType == "party" then
                Comms.Chat(tostring(finalOutput), "PARTY", nil, nil, true)
            else
                local chatService = Services.Chat
                if chatService and chatService.Print then
                    chatService:Print(tostring(finalOutput))
                else
                    addon:info("%s", tostring(finalOutput))
                end
            end
            return true
        end

        for _, c in ipairs(chList) do
            if type(c) == "number" then
                Comms.Chat(tostring(finalOutput), "CHANNEL", nil, c, true)
            else
                Comms.Chat(tostring(finalOutput), upper(c), nil, nil, true)
            end
        end

        return true
    end

    -- Tab
    function module:Tab(a, b)
        local target
        if IsShiftKeyDown() and _G[frameName .. b] ~= nil then
            target = _G[frameName .. b]
        elseif _G[frameName .. a] ~= nil then
            target = _G[frameName .. a]
        end
        if target then
            target:SetFocus()
        end
    end

    -- Clear
    function module:Clear()
        for k, _ in pairs(KRT_Spammer) do
            if k ~= "Channels" then
                KRT_Spammer[k] = nil
            end
        end

        finalOutput = DEFAULT_OUTPUT
        resetLastState()

        module:Stop()

        for _, field in ipairs(resetFields) do
            Frames.ResetEditBox(_G[frameName .. field])
        end

        local durationBox = _G[frameName .. "Duration"]
        KRT_Spammer.Duration = DEFAULT_DURATION_STR
        duration = DEFAULT_DURATION_STR

        if durationBox then
            Frames.ResetEditBox(durationBox)
            durationBox:SetText(DEFAULT_DURATION_STR)
        end

        loaded = false
        previewDirty = true

        -- FIX: reset UI immediately (len/255 included)
        resetLengthUI()
        updateControls()
    end

    -- Localize UI
    function UI.Localize()
        if UI.Localized then
            return
        end

        _G[frameName .. "NameStr"]:SetText(L.StrRaid)
        _G[frameName .. "DurationStr"]:SetText(L.StrDuration)
        _G[frameName .. "Tick"]:SetText("")
        _G[frameName .. "CompStr"]:SetText(L.StrSpammerCompStr)
        _G[frameName .. "NeedStr"]:SetText(L.StrSpammerNeedStr)
        _G[frameName .. "ClassStr"]:SetText(L.StrClass)
        _G[frameName .. "TanksStr"]:SetText(L.StrTank)
        _G[frameName .. "HealersStr"]:SetText(L.StrHealer)
        _G[frameName .. "MeleesStr"]:SetText(L.StrMelee)
        _G[frameName .. "RangedStr"]:SetText(L.StrRanged)
        _G[frameName .. "MessageStr"]:SetText(L.StrSpammerMessageStr)
        _G[frameName .. "ChannelsStr"]:SetText(L.StrChannels)
        for i = 1, 8 do
            local label = _G[frameName .. "Channel" .. i .. "Str"]
            if label then
                label:SetText(tostring(i))
            end
        end
        _G[frameName .. "ChannelGuildStr"]:SetText(L.StrGuild)
        _G[frameName .. "ChannelYellStr"]:SetText(L.StrYell)
        _G[frameName .. "PreviewStr"]:SetText(L.StrSpammerPreviewStr)
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "StartBtn"]:SetText(L.BtnStart)

        Frames.SetFrameTitle(frameName, L.StrSpammer)

        local durationBox = _G[frameName .. "Duration"]
        durationBox.tooltip_title = AUCTION_DURATION
        Frames.SetTooltip(durationBox, L.StrSpammerDurationHelp)

        local messageBox = _G[frameName .. "Message"]
        messageBox.tooltip_title = L.StrMessage
        Frames.SetTooltip(messageBox, {
            L.StrSpammerMessageHelp1,
            L.StrSpammerMessageHelp2,
            L.StrSpammerMessageHelp3,
        })

        local function setupEditBox(target)
            local box = _G[frameName .. target]
            if not box then
                return
            end

            box:SetScript("OnEditFocusGained", function()
                if ticking and not paused then
                    module:Pause()
                end
            end)

            box:SetScript("OnTextChanged", function(_, isUserInput)
                if inputsLocked then
                    return
                end
                if isUserInput then
                    previewDirty = true
                    module:RequestRefresh()
                end
            end)

            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            box:SetScript("OnEditFocusLost", function(self)
                module:Save(self)
            end)
        end

        for _, f in ipairs(inputFields) do
            setupEditBox(f)
        end

        -- Initialize default UI length once
        resetLengthUI()

        UI.Localized = true
    end

    -- Tick display
    function updateTickDisplay()
        if countdownRemaining > 0 then
            _G[frameName .. "Tick"]:SetText(countdownRemaining)
        else
            _G[frameName .. "Tick"]:SetText("")
        end
    end

    -- Lock/unlock inputs
    function setInputsLocked(locked)
        if inputsLocked == locked then
            return
        end
        inputsLocked = locked

        local alpha = locked and 0.7 or 1.0

        local function setEditBoxState(box, enabled)
            if not box then
                return
            end
            if box.SetEnabled then
                box:SetEnabled(enabled)
            elseif enabled and box.Enable then
                box:Enable()
            elseif not enabled and box.Disable then
                box:Disable()
            end
        end

        for _, field in ipairs(inputFields) do
            local box = _G[frameName .. field]
            if box then
                setEditBoxState(box, not locked)
                box:SetAlpha(alpha)
                if locked then
                    box:ClearFocus()
                end
            end
        end

        for i = 1, 8 do
            UIPrimitives.EnableDisable(_G[frameName .. "Chat" .. i], not locked)
        end
        UIPrimitives.EnableDisable(_G[frameName .. "ChatGuild"], not locked)
        UIPrimitives.EnableDisable(_G[frameName .. "ChatYell"], not locked)
        UIPrimitives.EnableDisable(_G[frameName .. "ClearBtn"], not locked)
    end

    -- Spam cycle
    function stopSpamCycle(resetCountdown)
        -- Stop and clear the spam ticker
        addon.CancelTimer(countdownTicker, true)
        countdownTicker = nil

        if resetCountdown then
            countdownRemaining = 0
        end

        updateTickDisplay()
    end

    function getValidDuration()
        local value = tonumber(duration)
        if not value or value <= 0 then
            value = DEFAULT_DURATION_NUM
        end
        return value
    end

    function startSpamCycle(resetCountdown)
        stopSpamCycle(false)

        local d = getValidDuration()
        if resetCountdown or countdownRemaining <= 0 then
            countdownRemaining = d
        end

        updateTickDisplay()

        countdownTicker = addon.NewTicker(1, function()
            if not ticking or paused then
                return
            end

            runElapsedSeconds = runElapsedSeconds + 1
            if runElapsedSeconds >= MAX_SPAM_RUNTIME_SECONDS then
                addon:warn(L.MsgSpammerAutoStopDuration:format(MAX_SPAM_RUNTIME_SECONDS))
                module:Stop()
                return
            end

            countdownRemaining = countdownRemaining - 1
            if countdownRemaining <= 0 then
                if not module:Spam() then
                    return
                end
                messagesSent = messagesSent + 1
                if messagesSent >= MAX_SPAM_MESSAGES_PER_RUN then
                    addon:warn(L.MsgSpammerAutoStopMessages:format(MAX_SPAM_MESSAGES_PER_RUN))
                    module:Stop()
                    return
                end
                countdownRemaining = getValidDuration()
            end

            updateTickDisplay()
        end)
    end

    -- Build output
    function buildOutput()
        local outBuf = { DEFAULT_OUTPUT }

        local name = lastState.name or ""
        if name ~= "" then
            outBuf[#outBuf + 1] = " "
            outBuf[#outBuf + 1] = name
        end

        local needParts = {}
        local function addNeed(n, label, class)
            n = tonumber(n) or 0
            if n > 0 then
                local s = n .. " " .. label
                if class and class ~= "" then
                    s = s .. " (" .. class .. ")"
                end
                needParts[#needParts + 1] = s
            end
        end

        addNeed(lastState.tank, L.StrTank, lastState.tankClass)
        addNeed(lastState.healer, L.StrHealer, lastState.healerClass)
        addNeed(lastState.melee, L.StrMelee, lastState.meleeClass)
        addNeed(lastState.ranged, L.StrRanged, lastState.rangedClass)

        if #needParts > 0 then
            outBuf[#outBuf + 1] = " - "
            outBuf[#outBuf + 1] = L.StrSpammerNeedStr
            outBuf[#outBuf + 1] = " "
            outBuf[#outBuf + 1] = tconcat(needParts, ", ")
        end

        if lastState.message and lastState.message ~= "" then
            outBuf[#outBuf + 1] = " - "
            outBuf[#outBuf + 1] = Strings.FindAchievement(lastState.message)
        end

        local temp = tconcat(outBuf)

        if temp ~= DEFAULT_OUTPUT then
            local total = (tonumber(lastState.tank) or 0) + (tonumber(lastState.healer) or 0) + (tonumber(lastState.melee) or 0) + (tonumber(lastState.ranged) or 0)

            local is25 = (name ~= "" and name:match("%f[%d]25%f[%D]")) ~= nil
            local max = is25 and 25 or 10
            temp = temp .. " (" .. (max - total) .. "/" .. max .. ")"
        end

        return temp
    end

    -- Controls update
    function updateControls()
        local locked = ticking and not paused
        local canStart = (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255)
        local btnLabel = paused and L.BtnResume or L.BtnStop
        local isStop = ticking == true

        if lastControls.locked == locked and lastControls.canStart == canStart and lastControls.btnLabel == btnLabel and lastControls.isStop == isStop then
            return
        end

        local frame = getFrame()
        if frame then
            setInputsLocked(locked)
        end

        UIPrimitives.SetText(_G[frameName .. "StartBtn"], btnLabel, L.BtnStart, isStop)
        UIPrimitives.EnableDisable(_G[frameName .. "StartBtn"], canStart)

        lastControls.locked = locked
        lastControls.canStart = canStart
        lastControls.btnLabel = btnLabel
        lastControls.isStop = isStop
    end

    -- Preview render
    function renderPreview()
        local frame = getFrame()
        if not frame or not frame:IsShown() then
            return
        end

        local changed = false

        for _, field in ipairs(previewFields) do
            local box = _G[frameName .. field.box]
            local value
            if field.number then
                value = tonumber(box:GetText()) or 0
            else
                value = Strings.TrimText(box:GetText())
            end

            if lastState[field.key] ~= value then
                lastState[field.key] = value
                changed = true
            end
        end

        local durationBox = _G[frameName .. "Duration"]
        local durationValue = durationBox and durationBox:GetText() or ""
        if durationValue == "" then
            durationValue = DEFAULT_DURATION_STR
            if durationBox then
                durationBox:SetText(durationValue)
            end
        end

        if lastState.duration ~= durationValue then
            lastState.duration = durationValue
            changed = true
        end

        if changed then
            finalOutput = buildOutput()

            local out = _G[frameName .. "Output"]
            if out then
                out:SetText(finalOutput)
            end

            local len = strlen(finalOutput)
            local lenText = _G[frameName .. "Length"]
            if lenText then
                lenText:SetText(len .. "/255")
                if finalOutput == DEFAULT_OUTPUT then
                    lenText:SetTextColor(0.5, 0.5, 0.5)
                elseif len <= 255 then
                    lenText:SetTextColor(0.0, 1.0, 0.0)
                else
                    lenText:SetTextColor(1.0, 0.0, 0.0)
                end
            end

            local msg = _G[frameName .. "Message"]
            if msg and msg.SetMaxLetters then
                if len <= 255 then
                    msg:SetMaxLetters(255)
                else
                    local messageValue = lastState.message or ""
                    msg:SetMaxLetters(strlen(messageValue) - 1)
                end
            end
        end

        duration = lastState.duration or DEFAULT_DURATION_STR
        KRT_Spammer.Duration = duration

        updateControls()
    end

    -- UI update tick
    function UI.Refresh()
        local frame = getFrame()
        if not (frame and frame:IsShown()) then
            return
        end

        if not loaded then
            KRT_Spammer.Duration = KRT_Spammer.Duration or DEFAULT_DURATION_STR

            resetAllChannelCheckboxes()

            for k, v in pairs(KRT_Spammer) do
                if k == "Channels" then
                    for i, c in ipairs(v) do
                        local id = tonumber(c) or select(1, GetChannelName(c))
                        id = (id and id > 0) and id or c
                        v[i] = id
                        setCheckbox("Chat" .. id, true)
                    end
                elseif _G[frameName .. k] then
                    _G[frameName .. k]:SetText(v)
                end
            end

            loaded = true
            previewDirty = true
        end

        if ticking and not paused then
            updateControls()
            updateTickDisplay()
            return
        end

        if previewDirty then
            renderPreview()
            previewDirty = false
        else
            updateControls()
            updateTickDisplay()
        end
    end

    function module:Refresh()
        UI.Refresh()
    end
end
