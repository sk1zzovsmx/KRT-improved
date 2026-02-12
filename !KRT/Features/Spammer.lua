--[[
    Features/Spammer.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Utils = feature.Utils

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local _G = _G
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local pairs, ipairs, type, select = pairs, ipairs, type, select
local find, strlen = string.find, string.len
local gsub, upper = string.gsub, string.upper
local tostring, tonumber = tostring, tonumber

-- =========== LFM Spam Module  =========== --
do
    addon.Spammer = addon.Spammer or {}
    local module = addon.Spammer
    -- ----- Internal state ----- --
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTSpammer")
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    -- Defaults / constants
    local DEFAULT_DURATION_STR = "60"
    local DEFAULT_DURATION_NUM = 60
    local DEFAULT_OUTPUT = "LFM"

    -- Runtime state
    local loaded = false

    -- Duration kept as string for coherence with EditBox/SV
    local duration = DEFAULT_DURATION_STR

    local finalOutput = DEFAULT_OUTPUT

    local ticking = false
    local paused = false
    local countdownTicker
    local countdownRemaining = 0

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
        { key = "name",        box = "Name" },
        { key = "tank",        box = "Tank",       number = true },
        { key = "tankClass",   box = "TankClass" },
        { key = "healer",      box = "Healer",     number = true },
        { key = "healerClass", box = "HealerClass" },
        { key = "melee",       box = "Melee",      number = true },
        { key = "meleeClass",  box = "MeleeClass" },
        { key = "ranged",      box = "Ranged",     number = true },
        { key = "rangedClass", box = "RangedClass" },
        { key = "message",     box = "Message" },
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
    local RenderPreview
    local StartSpamCycle
    local StopSpamCycle
    local UpdateControls
    local BuildOutput
    local UpdateTickDisplay
    local SetInputsLocked
    local GetValidDuration

    -- Small helpers
    local function ResetLastState()
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

    local function SetCheckbox(suffix, checked)
        local chk = _G[frameName .. suffix]
        if chk and chk.SetChecked then
            chk:SetChecked(checked and true or false)
        end
    end

    local function ResetAllChannelCheckboxes()
        for i = 1, 8 do
            SetCheckbox("Chat" .. i, false)
        end
        SetCheckbox("ChatGuild", false)
        SetCheckbox("ChatYell", false)
    end

    -- Deterministic: sync Duration immediately from UI/SV (no waiting for preview tick)
    local function SyncDurationNow()
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
    local function EnsureReadyForStart()
        SyncDurationNow()

        local frame = getFrame()
        if frame and frame:IsShown() then
            if previewDirty or not finalOutput or finalOutput == "" then
                RenderPreview()
                previewDirty = false
            end
        end
    end

    local function ResetLengthUI()
        local frame = getFrame()
        if not frame then return end
        local len = strlen(DEFAULT_OUTPUT)
        local lenStr = len .. "/255"

        local out = _G[frameName .. "Output"]
        if out then out:SetText(DEFAULT_OUTPUT) end

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

    -- OnLoad frame
    function module:OnLoad(frame)
        if not frame then return end

        module.frame = frame
        frameName = frame:GetName()

        -- Drag registration kept in Lua (avoid template logic in XML).
        Utils.enableDrag(frame)

        -- Localize once (not per tick)
        LocalizeUIFrame()

        frame:SetScript("OnShow", function()
            module:RequestRefresh()
        end)

        if frame:IsShown() then
            module:RequestRefresh()
        end
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = addon:makeUIFrameController(getFrame, function() module:RequestRefresh() end)
    bindModuleToggleHide(module, uiController)

    -- Save (EditBox / Checkbox)
    function module:Save(box)
        if not box then return end

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
            local value = Utils.trimText(box:GetText())
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
        EnsureReadyForStart()

        if addon.WithinRange(strlen(finalOutput), 4, 255) then
            if paused then
                paused = false
                SetInputsLocked(true)
                StartSpamCycle(false)
            elseif ticking then
                ticking = false
                paused = false
                StopSpamCycle(true)
                SetInputsLocked(false)
            else
                ticking = true
                paused = false
                SetInputsLocked(true)
                StartSpamCycle(true)
            end
            module:RequestRefresh()
        end
    end

    function module:Stop()
        ticking = false
        paused = false
        StopSpamCycle(true)
        SetInputsLocked(false)
        module:RequestRefresh()
    end

    function module:Pause()
        if not ticking or paused then return end
        paused = true
        StopSpamCycle(false)
        SetInputsLocked(false)
        module:RequestRefresh()
    end

    -- Spam
    function module:Spam()
        if strlen(finalOutput) > 255 then
            addon:error(L.StrSpammerErrLength)
            ticking = false
            return
        end

        local chList = KRT_Spammer.Channels or {}

        -- CHANGE: fallback SAY (not YELL)
        if #chList <= 0 then
            Utils.chat(tostring(finalOutput), "SAY", nil, nil, true)
            return
        end

        for _, c in ipairs(chList) do
            if type(c) == "number" then
                Utils.chat(tostring(finalOutput), "CHANNEL", nil, c, true)
            else
                Utils.chat(tostring(finalOutput), upper(c), nil, nil, true)
            end
        end
    end

    -- Tab
    function module:Tab(a, b)
        local target
        if IsShiftKeyDown() and _G[frameName .. b] ~= nil then
            target = _G[frameName .. b]
        elseif _G[frameName .. a] ~= nil then
            target = _G[frameName .. a]
        end
        if target then target:SetFocus() end
    end

    -- Clear
    function module:Clear()
        for k, _ in pairs(KRT_Spammer) do
            if k ~= "Channels" then
                KRT_Spammer[k] = nil
            end
        end

        finalOutput = DEFAULT_OUTPUT
        ResetLastState()

        module:Stop()

        for _, field in ipairs(resetFields) do
            Utils.resetEditBox(_G[frameName .. field])
        end

        local durationBox = _G[frameName .. "Duration"]
        KRT_Spammer.Duration = DEFAULT_DURATION_STR
        duration = DEFAULT_DURATION_STR

        if durationBox then
            Utils.resetEditBox(durationBox)
            durationBox:SetText(DEFAULT_DURATION_STR)
        end

        loaded = false
        previewDirty = true

        -- FIX: reset UI immediately (len/255 included)
        ResetLengthUI()
        UpdateControls()
    end

    -- Localize UI
    function LocalizeUIFrame()
        if localized then return end

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

        Utils.setFrameTitle(frameName, L.StrSpammer)
        _G[frameName .. "StartBtn"]:SetScript("OnClick", module.Start)

        local durationBox = _G[frameName .. "Duration"]
        durationBox.tooltip_title = AUCTION_DURATION
        addon:SetTooltip(durationBox, L.StrSpammerDurationHelp)

        local messageBox = _G[frameName .. "Message"]
        messageBox.tooltip_title = L.StrMessage
        addon:SetTooltip(messageBox, {
            L.StrSpammerMessageHelp1,
            L.StrSpammerMessageHelp2,
            L.StrSpammerMessageHelp3,
        })

        local function setupEditBox(target)
            local box = _G[frameName .. target]
            if not box then return end

            box:SetScript("OnEditFocusGained", function()
                if ticking and not paused then
                    module:Pause()
                end
            end)

            box:SetScript("OnTextChanged", function(_, isUserInput)
                if inputsLocked then return end
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
        ResetLengthUI()

        localized = true
    end

    -- Tick display
    function UpdateTickDisplay()
        if countdownRemaining > 0 then
            _G[frameName .. "Tick"]:SetText(countdownRemaining)
        else
            _G[frameName .. "Tick"]:SetText("")
        end
    end

    -- Lock/unlock inputs
    function SetInputsLocked(locked)
        if inputsLocked == locked then return end
        inputsLocked = locked

        local alpha = locked and 0.7 or 1.0

        local function setEditBoxState(box, enabled)
            if not box then return end
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
            Utils.enableDisable(_G[frameName .. "Chat" .. i], not locked)
        end
        Utils.enableDisable(_G[frameName .. "ChatGuild"], not locked)
        Utils.enableDisable(_G[frameName .. "ChatYell"], not locked)
        Utils.enableDisable(_G[frameName .. "ClearBtn"], not locked)
    end

    -- Spam cycle
    function StopSpamCycle(resetCountdown)
        -- Stop and clear the spam ticker
        addon.CancelTimer(countdownTicker, true)
        countdownTicker = nil

        if resetCountdown then
            countdownRemaining = 0
        end

        UpdateTickDisplay()
    end

    function GetValidDuration()
        local value = tonumber(duration)
        if not value or value <= 0 then
            value = DEFAULT_DURATION_NUM
        end
        return value
    end

    function StartSpamCycle(resetCountdown)
        StopSpamCycle(false)

        local d = GetValidDuration()
        if resetCountdown or countdownRemaining <= 0 then
            countdownRemaining = d
        end

        UpdateTickDisplay()

        countdownTicker = addon.NewTicker(1, function()
            if not ticking or paused then return end

            countdownRemaining = countdownRemaining - 1
            if countdownRemaining <= 0 then
                module:Spam()
                countdownRemaining = GetValidDuration()
            end

            UpdateTickDisplay()
        end)
    end

    -- Build output
    function BuildOutput()
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

        addNeed(lastState.tank, "Tank", lastState.tankClass)
        addNeed(lastState.healer, "Healer", lastState.healerClass)
        addNeed(lastState.melee, "Melee", lastState.meleeClass)
        addNeed(lastState.ranged, "Ranged", lastState.rangedClass)

        if #needParts > 0 then
            outBuf[#outBuf + 1] = " - Need "
            outBuf[#outBuf + 1] = tconcat(needParts, ", ")
        end

        if lastState.message and lastState.message ~= "" then
            outBuf[#outBuf + 1] = " - "
            outBuf[#outBuf + 1] = Utils.findAchievement(lastState.message)
        end

        local temp = tconcat(outBuf)

        if temp ~= DEFAULT_OUTPUT then
            local total =
                (tonumber(lastState.tank) or 0) +
                (tonumber(lastState.healer) or 0) +
                (tonumber(lastState.melee) or 0) +
                (tonumber(lastState.ranged) or 0)

            local is25 = (name ~= "" and name:match("%f[%d]25%f[%D]")) ~= nil
            local max = is25 and 25 or 10
            temp = temp .. " (" .. (max - total) .. "/" .. max .. ")"
        end

        return temp
    end

    -- Controls update
    function UpdateControls()
        local locked = ticking and not paused
        local canStart = (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255)
        local btnLabel = paused and L.BtnResume or L.BtnStop
        local isStop = ticking == true

        if lastControls.locked == locked and
            lastControls.canStart == canStart and
            lastControls.btnLabel == btnLabel and
            lastControls.isStop == isStop then
            return
        end

        local frame = getFrame()
        if frame then
            SetInputsLocked(locked)
        end

        Utils.setText(_G[frameName .. "StartBtn"], btnLabel, L.BtnStart, isStop)
        Utils.enableDisable(_G[frameName .. "StartBtn"], canStart)

        lastControls.locked = locked
        lastControls.canStart = canStart
        lastControls.btnLabel = btnLabel
        lastControls.isStop = isStop
    end

    -- Preview render
    function RenderPreview()
        local frame = getFrame()
        if not frame or not frame:IsShown() then return end

        local changed = false

        for _, field in ipairs(previewFields) do
            local box = _G[frameName .. field.box]
            local value
            if field.number then
                value = tonumber(box:GetText()) or 0
            else
                value = Utils.trimText(box:GetText())
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
            if durationBox then durationBox:SetText(durationValue) end
        end

        if lastState.duration ~= durationValue then
            lastState.duration = durationValue
            changed = true
        end

        if changed then
            finalOutput = BuildOutput()

            local out = _G[frameName .. "Output"]
            if out then out:SetText(finalOutput) end

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

        UpdateControls()
    end

    -- UI update tick
    function UpdateUIFrame()
        local frame = getFrame()
        if not (frame and frame:IsShown()) then
            return
        end

        if not loaded then
            KRT_Spammer.Duration = KRT_Spammer.Duration or DEFAULT_DURATION_STR

            ResetAllChannelCheckboxes()

            for k, v in pairs(KRT_Spammer) do
                if k == "Channels" then
                    for i, c in ipairs(v) do
                        local id = tonumber(c) or select(1, GetChannelName(c))
                        id = (id and id > 0) and id or c
                        v[i] = id
                        SetCheckbox("Chat" .. id, true)
                    end
                elseif _G[frameName .. k] then
                    _G[frameName .. k]:SetText(v)
                end
            end

            loaded = true
            previewDirty = true
        end

        if ticking and not paused then
            UpdateControls()
            UpdateTickDisplay()
            return
        end

        if previewDirty then
            RenderPreview()
            previewDirty = false
        else
            UpdateControls()
            UpdateTickDisplay()
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    bindModuleRequestRefresh(module, getFrame)
end
