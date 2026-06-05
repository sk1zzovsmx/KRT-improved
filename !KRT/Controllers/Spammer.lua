-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Database = feature.Database

local Frames = feature.Frames
local Strings = feature.Strings
local Services = feature.Services
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local pairs, ipairs, type, select = pairs, ipairs, type, select
local find, strlen = string.find, string.len
local gsub = string.gsub
local tostring, tonumber = tostring, tonumber

local requireServiceMethod = Database.RequireServiceMethod

local Chat = Services.Chat
local ChatApi = {
    GetSpamRuntimeState = requireServiceMethod("Chat", Chat, "GetSpamRuntimeState"),
    StartSpamCycle = requireServiceMethod("Chat", Chat, "StartSpamCycle"),
    StopSpamCycle = requireServiceMethod("Chat", Chat, "StopSpamCycle"),
    PauseSpamCycle = requireServiceMethod("Chat", Chat, "PauseSpamCycle"),
}

-- =========== LFM Spam Module  =========== --
do
    addon.Controllers.Spammer = addon.Controllers.Spammer or {}
    local module = addon.Controllers.Spammer
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui
    -- ----- Internal state ----- --

    local getFrame = makeModuleFrameGetter(module, "KRTSpammer")
    -- Defaults / constants
    local DEFAULT_DURATION_STR = "60"
    local DEFAULT_OUTPUT = "LFM"

    -- Runtime state
    local loaded = false

    -- Duration kept as string for coherence with EditBox/SV
    local duration = DEFAULT_DURATION_STR

    local finalOutput = DEFAULT_OUTPUT

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
    local updateControls
    local updateTickDisplay
    local setInputsLocked
    local saveSpammer
    local startSpam
    local stopSpam
    local pauseSpam
    local focusTab
    local clearSpammer

    -- ----- Private helpers ----- --
    local function getSpammerStore()
        if type(KRT_Spammer) ~= "table" then
            KRT_Spammer = {}
        end
        return KRT_Spammer
    end

    local function getSpammerChannels(store)
        store = store or getSpammerStore()
        if type(store.Channels) ~= "table" then
            store.Channels = {}
        end
        return store.Channels
    end

    function UI.AcquireRefs(frame)
        local refs = {
            clearBtn = Frames.GetRef(frame, "ClearBtn"),
            startBtn = Frames.GetRef(frame, "StartBtn"),
            duration = Frames.GetRef(frame, "Duration"),
            healer = Frames.GetRef(frame, "Healer"),
            healerClass = Frames.GetRef(frame, "HealerClass"),
            melee = Frames.GetRef(frame, "Melee"),
            meleeClass = Frames.GetRef(frame, "MeleeClass"),
            message = Frames.GetRef(frame, "Message"),
            name = Frames.GetRef(frame, "Name"),
            ranged = Frames.GetRef(frame, "Ranged"),
            rangedClass = Frames.GetRef(frame, "RangedClass"),
            tank = Frames.GetRef(frame, "Tank"),
            tankClass = Frames.GetRef(frame, "TankClass"),
            chatGuild = Frames.GetRef(frame, "ChatGuild"),
            chatYell = Frames.GetRef(frame, "ChatYell"),
            channels = {},
        }
        for i = 1, 8 do
            refs.channels[i] = Frames.GetRef(frame, "Chat" .. i)
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

    local function getNamedPart(suffix)
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
        return _G[frameName .. suffix]
    end

    local function setCheckbox(suffix, checked)
        local chk = getNamedPart(suffix)
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

    local function getSpamRuntimeState()
        return ChatApi.GetSpamRuntimeState(Chat)
    end

    local function buildSpammerOutput(state, defaultOutput)
        local baseOutput = defaultOutput or DEFAULT_OUTPUT
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

    -- Deterministic: sync Duration immediately from UI/SV (no waiting for preview tick)
    local function syncDurationNow()
        local value
        local frame = getFrame()
        local store = getSpammerStore()

        if frame and frame:IsShown() then
            local box = getNamedPart("Duration")
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
            value = store.Duration or DEFAULT_DURATION_STR
            value = tostring(value)
        end

        duration = value
        lastState.duration = value
        store.Duration = value
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

        local out = getNamedPart("Output")
        if out then
            out:SetText(DEFAULT_OUTPUT)
        end

        local lengthText = getNamedPart("Length")
        if lengthText then
            lengthText:SetText(lenStr)
            lengthText:SetTextColor(0.5, 0.5, 0.5)
        end

        local msg = getNamedPart("Message")
        if msg and msg.SetMaxLetters then
            msg:SetMaxLetters(255)
        end
    end

    -- ----- Public methods ----- --
    local function loadSpammerFrame(frame)
        UI.FrameName = Frames.BindModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                module:RequestRefresh()
            end,
        }) or UI.FrameName
        UI.Loaded = UI.FrameName ~= nil
        if not UI.Loaded then
            return
        end

        if frame:IsShown() then
            module:RequestRefresh()
        end
    end

    local function BindHandlers(_, _, refs)
        Frames.SetScriptSafely(refs.clearBtn, "OnClick", function()
            clearSpammer()
        end)
        Frames.SetScriptSafely(refs.startBtn, "OnClick", function()
            startSpam()
        end)

        Frames.SetScriptSafely(refs.duration, "OnTabPressed", function()
            focusTab("Tank", "Name")
        end)
        Frames.SetScriptSafely(refs.healer, "OnTabPressed", function()
            focusTab("HealerClass", "TankClass")
        end)
        Frames.SetScriptSafely(refs.healerClass, "OnTabPressed", function()
            focusTab("Melee", "Healer")
        end)
        Frames.SetScriptSafely(refs.melee, "OnTabPressed", function()
            focusTab("MeleeClass", "HealerClass")
        end)
        Frames.SetScriptSafely(refs.meleeClass, "OnTabPressed", function()
            focusTab("Ranged", "Melee")
        end)
        Frames.SetScriptSafely(refs.message, "OnTabPressed", function()
            focusTab("Name", "RangedClass")
        end)
        Frames.SetScriptSafely(refs.name, "OnTabPressed", function()
            focusTab("Duration", "Message")
        end)
        Frames.SetScriptSafely(refs.ranged, "OnTabPressed", function()
            focusTab("RangedClass", "MeleeClass")
        end)
        Frames.SetScriptSafely(refs.rangedClass, "OnTabPressed", function()
            focusTab("Message", "Ranged")
        end)
        Frames.SetScriptSafely(refs.tank, "OnTabPressed", function()
            focusTab("TankClass", "Duration")
        end)
        Frames.SetScriptSafely(refs.tankClass, "OnTabPressed", function()
            focusTab("Healer", "Tank")
        end)

        for i = 1, #refs.channels do
            local channelBox = refs.channels[i]
            Frames.SetScriptSafely(channelBox, "OnClick", function(self, button)
                saveSpammer(self, button)
            end)
        end
        Frames.SetScriptSafely(refs.chatGuild, "OnClick", function(self, button)
            saveSpammer(self, button)
        end)
        Frames.SetScriptSafely(refs.chatYell, "OnClick", function(self, button)
            saveSpammer(self, button)
        end)
    end

    local function OnLoadFrame(frame)
        loadSpammerFrame(frame)
        return UI.FrameName
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
        refresh = function()
            if not UI.Localized then
                UI.Localize()
            end
            UI.Refresh()
        end,
    })

    -- Save (EditBox / Checkbox)
    saveSpammer = function(box)
        if not box then
            return
        end

        local frameName = UI.FrameName
        if not frameName then
            return
        end

        local boxName = box:GetName()
        local target = gsub(boxName, frameName, "")
        local store = getSpammerStore()

        if find(target, "Chat") then
            local channels = getSpammerChannels(store)

            local channel = gsub(target, "Chat", "")
            local id = tonumber(channel) or select(1, GetChannelName(channel))
            channel = (id and id > 0) and id or channel

            -- FIX: GetChecked can be true/false or 1/0
            local checked = box:GetChecked()
            checked = (checked == true or checked == 1)

            local existed = tContains(channels, channel)
            if checked and not existed then
                tinsert(channels, channel)
            elseif not checked and existed then
                local i = addon.tIndexOf(channels, channel)
                while i do
                    tremove(channels, i)
                    i = addon.tIndexOf(channels, channel)
                end
            end
        else
            local value = Strings.TrimText(box:GetText())
            value = (value == "") and nil or value
            store[target] = value
            box:ClearFocus()
        end

        loaded = false
        previewDirty = true
        module:RequestRefresh()
    end

    -- Start/Stop/Pause
    local function refreshSpamUi()
        module:RequestRefresh()
    end

    local function unlockSpamInputsAndRefresh()
        setInputsLocked(false)
        module:RequestRefresh()
    end

    startSpam = function()
        ensureReadyForStart()
        local store = getSpammerStore()

        if not addon.WithinRange(strlen(finalOutput), 4, 255) then
            return
        end

        local runtime = getSpamRuntimeState()
        if runtime.ticking and runtime.paused then
            setInputsLocked(true)
            ChatApi.StartSpamCycle(Chat, {
                duration = duration,
                output = finalOutput,
                channels = getSpammerChannels(store),
                resetCountdown = false,
                resetRun = false,
                onTick = refreshSpamUi,
                onAutoStop = unlockSpamInputsAndRefresh,
            })
        elseif runtime.ticking then
            ChatApi.StopSpamCycle(Chat, true, true)
            setInputsLocked(false)
        else
            setInputsLocked(true)
            ChatApi.StartSpamCycle(Chat, {
                duration = duration,
                output = finalOutput,
                channels = getSpammerChannels(store),
                resetCountdown = true,
                resetRun = true,
                onTick = refreshSpamUi,
                onAutoStop = unlockSpamInputsAndRefresh,
            })
        end

        module:RequestRefresh()
    end

    stopSpam = function()
        ChatApi.StopSpamCycle(Chat, true, true)
        setInputsLocked(false)
        module:RequestRefresh()
    end

    function module:RequestStart()
        return startSpam()
    end

    function module:RequestStop()
        return stopSpam()
    end

    pauseSpam = function()
        local pausedOk = ChatApi.PauseSpamCycle(Chat)
        if not pausedOk then
            return
        end

        setInputsLocked(false)
        module:RequestRefresh()
    end

    -- Tab
    focusTab = function(a, b)
        local target
        if IsShiftKeyDown() and getNamedPart(b) ~= nil then
            target = getNamedPart(b)
        elseif getNamedPart(a) ~= nil then
            target = getNamedPart(a)
        end
        if target then
            target:SetFocus()
        end
    end

    -- Clear
    clearSpammer = function()
        local store = getSpammerStore()
        for k, _ in pairs(store) do
            if k ~= "Channels" then
                store[k] = nil
            end
        end

        finalOutput = DEFAULT_OUTPUT
        resetLastState()

        stopSpam()

        for _, field in ipairs(resetFields) do
            Frames.ResetEditBox(getNamedPart(field))
        end

        local durationBox = getNamedPart("Duration")
        store.Duration = DEFAULT_DURATION_STR
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
        local frameName = UI.FrameName
        if not frameName then
            return
        end

        getNamedPart("NameStr"):SetText(L.StrRaid)
        getNamedPart("DurationStr"):SetText(L.StrDuration)
        getNamedPart("Tick"):SetText("")
        getNamedPart("CompStr"):SetText(L.StrSpammerCompStr)
        getNamedPart("NeedStr"):SetText(L.StrSpammerNeedStr)
        getNamedPart("ClassStr"):SetText(L.StrClass)
        getNamedPart("TanksStr"):SetText(L.StrTank)
        getNamedPart("HealersStr"):SetText(L.StrHealer)
        getNamedPart("MeleesStr"):SetText(L.StrMelee)
        getNamedPart("RangedStr"):SetText(L.StrRanged)
        getNamedPart("MessageStr"):SetText(L.StrSpammerMessageStr)
        getNamedPart("ChannelsStr"):SetText(L.StrChannels)
        for i = 1, 8 do
            local label = getNamedPart("Channel" .. i .. "Str")
            if label then
                label:SetText(tostring(i))
            end
        end
        getNamedPart("ChannelGuildStr"):SetText(L.StrGuild)
        getNamedPart("ChannelYellStr"):SetText(L.StrYell)
        getNamedPart("PreviewStr"):SetText(L.StrSpammerPreviewStr)
        getNamedPart("ClearBtn"):SetText(L.BtnClear)
        getNamedPart("StartBtn"):SetText(L.BtnStart)

        Frames.SetFrameTitle(frameName, L.StrSpammer)

        local durationBox = getNamedPart("Duration")
        durationBox.tooltip_title = AUCTION_DURATION
        Frames.SetTooltip(durationBox, L.StrSpammerDurationHelp)

        local messageBox = getNamedPart("Message")
        messageBox.tooltip_title = L.StrMessage
        Frames.SetTooltip(messageBox, {
            L.StrSpammerMessageHelp1,
            L.StrSpammerMessageHelp2,
            L.StrSpammerMessageHelp3,
        })

        local function setupEditBox(target)
            local box = getNamedPart(target)
            if not box then
                return
            end

            Frames.SetScriptSafely(box, "OnEditFocusGained", function()
                local runtime = getSpamRuntimeState()
                if runtime.ticking and not runtime.paused then
                    pauseSpam()
                end
            end)

            Frames.SetScriptSafely(box, "OnTextChanged", function(_, isUserInput)
                if inputsLocked then
                    return
                end
                if isUserInput then
                    previewDirty = true
                    module:RequestRefresh()
                end
            end)

            Frames.SetScriptSafely(box, "OnEnterPressed", function(self)
                self:ClearFocus()
            end)

            Frames.SetScriptSafely(box, "OnEditFocusLost", function(self)
                saveSpammer(self)
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
    updateTickDisplay = function()
        local runtime = getSpamRuntimeState()
        local countdownRemaining = tonumber(runtime.countdownRemaining) or 0
        local tickText = getNamedPart("Tick")
        if not tickText then
            return
        end
        if countdownRemaining > 0 then
            tickText:SetText(countdownRemaining)
        else
            tickText:SetText("")
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
            local box = getNamedPart(field)
            if box then
                setEditBoxState(box, not locked)
                box:SetAlpha(alpha)
                if locked then
                    box:ClearFocus()
                end
            end
        end

        for i = 1, 8 do
            UIPrimitives.EnableDisable(getNamedPart("Chat" .. i), not locked)
        end
        UIPrimitives.EnableDisable(getNamedPart("ChatGuild"), not locked)
        UIPrimitives.EnableDisable(getNamedPart("ChatYell"), not locked)
        UIPrimitives.EnableDisable(getNamedPart("ClearBtn"), not locked)
    end

    -- Controls update
    function updateControls()
        local runtime = getSpamRuntimeState()
        local locked = runtime.ticking and not runtime.paused
        local canStart = (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255)
        local btnLabel = runtime.paused and L.BtnResume or L.BtnStop
        local isStop = runtime.ticking == true

        if lastControls.locked == locked and lastControls.canStart == canStart and lastControls.btnLabel == btnLabel and lastControls.isStop == isStop then
            return
        end

        local frame = getFrame()
        if frame then
            setInputsLocked(locked)
        end

        UIPrimitives.SetText(getNamedPart("StartBtn"), btnLabel, L.BtnStart, isStop)
        UIPrimitives.EnableDisable(getNamedPart("StartBtn"), canStart)

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
            local box = getNamedPart(field.box)
            local value
            if field.number then
                value = box and (tonumber(box:GetText()) or 0) or 0
            else
                value = box and Strings.TrimText(box:GetText()) or ""
            end

            if lastState[field.key] ~= value then
                lastState[field.key] = value
                changed = true
            end
        end

        local durationBox = getNamedPart("Duration")
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
            finalOutput = buildSpammerOutput(lastState, DEFAULT_OUTPUT)

            local out = getNamedPart("Output")
            if out then
                out:SetText(finalOutput)
            end

            local len = strlen(finalOutput)
            local lenText = getNamedPart("Length")
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

            local msg = getNamedPart("Message")
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
        local store = getSpammerStore()
        store.Duration = duration

        updateControls()
    end

    -- UI update tick
    function UI.Refresh()
        local frame = getFrame()
        if not (frame and frame:IsShown()) then
            return
        end

        if not loaded then
            local store = getSpammerStore()
            store.Duration = store.Duration or DEFAULT_DURATION_STR

            resetAllChannelCheckboxes()

            for k, v in pairs(store) do
                if k == "Channels" then
                    for i, c in ipairs(v) do
                        local id = tonumber(c) or select(1, GetChannelName(c))
                        id = (id and id > 0) and id or c
                        v[i] = id
                        setCheckbox("Chat" .. id, true)
                    end
                elseif getNamedPart(k) then
                    getNamedPart(k):SetText(v)
                end
            end

            loaded = true
            previewDirty = true
        end

        local runtime = getSpamRuntimeState()
        if runtime.ticking and not runtime.paused then
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
end

local registry = addon.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Controllers/Spammer", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Chat",
        },
    })
    registry.SetLoaded("Controllers/Spammer")
end
