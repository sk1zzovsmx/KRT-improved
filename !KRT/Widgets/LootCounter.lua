-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L

local Frames = feature.Frames or addon.Frames
local Colors = feature.Colors or addon.Colors
local UIScaffold = addon.UIScaffold
local Events = feature.Events or addon.Events
local C = feature.C
local Core = feature.Core or addon.Core
local Bus = feature.Bus or addon.Bus
local Services = feature.Services or addon.Services

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local twipe = table.wipe
local tsort = table.sort

local type, tostring, tonumber = type, tostring, tonumber
local strlen = string.len

local InternalEvents = Events.Internal
local UIFacade = addon.UI

-- Loot counter module.
-- Tracks and edits item distribution counts (MS wins).
do
    if not UIFacade:IsEnabled("LootCounter") then
        return
    end

    addon.Widgets.LootCounter = addon.Widgets.LootCounter or {}
    local module = addon.Widgets.LootCounter
    module._ui = module._ui
        or {
            Loaded = false,
            Bound = false,
            Localized = false,
            Dirty = true,
            Reason = nil,
            FrameName = nil,
        }
    local UI = module._ui

    -- ----- Internal state ----- --
    local rows, raidPlayers = {}, {}
    local scrollFrame, scrollChild, header
    local getFrame = makeModuleFrameGetter(module, "KRTLootCounterFrame")

    -- Single-line column header.
    local HEADER_HEIGHT = 18

    -- Layout constants (columns: Name | Count | Actions)
    local BTN_W, BTN_H = 20, 18
    local BTN_GAP = 2
    local COL_GAP = 8
    local ACTION_COL_W = (BTN_W * 3) + (BTN_GAP * 2) + 2 -- (+/-/R + gaps + right pad)
    local COUNT_COL_W = 40
    local CHAT_MSG_MAX_LEN = 255
    local RESET_ALL_POPUP_KEY = "KRT_LOOTCOUNTER_RESET_ALL"

    -- ----- Private helpers ----- --
    function UI.AcquireRefs(frame)
        local refs = {
            scrollFrame = frame and (frame.ScrollFrame or _G[(frame.GetName and frame:GetName() or "KRTLootCounterFrame") .. "ScrollFrame"]) or nil,
            announceBtn = Frames.Ref(frame, "AnnounceBtn"),
            resetAllBtn = Frames.Ref(frame, "ResetAllBtn"),
        }
        refs.scrollChild = (refs.scrollFrame and refs.scrollFrame.ScrollChild) or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        return refs
    end

    local function getAnnounceButton()
        local refs = module.refs
        if refs and refs.announceBtn then
            return refs.announceBtn
        end
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
        return _G[frameName .. "AnnounceBtn"]
    end

    local function getResetAllButton()
        local refs = module.refs
        if refs and refs.resetAllBtn then
            return refs.resetAllBtn
        end
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
        return _G[frameName .. "ResetAllBtn"]
    end

    local function ensureResetAllPopup()
        if not StaticPopupDialogs then
            return false
        end
        if StaticPopupDialogs[RESET_ALL_POPUP_KEY] then
            return true
        end

        Frames.MakeConfirmPopup(RESET_ALL_POPUP_KEY, L.StrConfirmLootCounterResetAll, function()
            module:ResetAllCounts()
        end)

        local popup = StaticPopupDialogs[RESET_ALL_POPUP_KEY]
        if popup then
            popup.preferredIndex = 3
            return true
        end
        return false
    end

    local function canBroadcastCounter()
        local raidService = Services.Raid
        if not (raidService and raidService.IsPlayerInRaid and raidService:IsPlayerInRaid()) then
            return false, "not_in_raid"
        end

        if type(addon.GetRaidCapabilityState) == "function" then
            local state = addon:GetRaidCapabilityState("changes_broadcast")
            if state and state.allowed == true then
                return true
            end
            return false, state and state.reason or "missing_leadership"
        end

        if type(addon.CanUseRaidCapability) == "function" then
            if addon:CanUseRaidCapability("changes_broadcast") then
                return true
            end
            return false, "missing_leadership"
        end

        if Core.GetUnitRank then
            local rank = tonumber(Core.GetUnitRank("player", 0)) or 0
            if rank > 0 then
                return true
            end
        end

        return false, "missing_leadership"
    end

    local function warnBroadcastDenied(reason)
        if reason == "missing_leadership" or reason == "missing_rank" then
            addon:warn(L.WarnLootCounterBroadcastNotAllowed)
        end
    end

    local function collectAnnounceGroups(players)
        local groupedByCount = {}
        local counts = {}

        for i = 1, #players do
            local row = players[i]
            local name = row and row.name
            local count = (row and tonumber(row.count)) or 0
            if name and name ~= "" and count > 0 then
                local bucket = groupedByCount[count]
                if not bucket then
                    bucket = {}
                    groupedByCount[count] = bucket
                    counts[#counts + 1] = count
                end
                bucket[#bucket + 1] = name
            end
        end

        tsort(counts)
        for i = 1, #counts do
            tsort(groupedByCount[counts[i]])
        end

        return groupedByCount, counts
    end

    local function appendBucketLines(outLines, count, names)
        if not names or #names <= 0 then
            return
        end

        local prefix = "+" .. tostring(count) .. ": "
        local line = prefix
        local hasNames = false

        for i = 1, #names do
            local name = names[i]
            local candidate
            if hasNames then
                candidate = line .. ", " .. name
            else
                candidate = line .. name
            end

            if hasNames and strlen(candidate) > CHAT_MSG_MAX_LEN then
                outLines[#outLines + 1] = line
                line = prefix .. name
            else
                line = candidate
            end
            hasNames = true
        end

        outLines[#outLines + 1] = line
    end

    function UI.Localize()
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        Frames.SetFrameTitle(frameName, L.StrLootCounter)
        local announceBtn = getAnnounceButton()
        if announceBtn then
            announceBtn:SetText(L.BtnLootCounterAnnounce)
            Frames.SetTooltip(announceBtn, L.TipLootCounterAnnounce)
        end
        local resetAllBtn = getResetAllButton()
        if resetAllBtn then
            resetAllBtn:SetText(L.BtnLootCounterResetAll)
            Frames.SetTooltip(resetAllBtn, L.TipLootCounterResetAll)
        end
    end

    local function ensureFrames()
        local frame = getFrame()
        if not frame then
            return false
        end

        UI.FrameName = UI.FrameName or (frame.GetName and frame:GetName()) or "KRTLootCounterFrame"
        scrollFrame = scrollFrame or frame.ScrollFrame or _G[UI.FrameName .. "ScrollFrame"] or _G["KRTLootCounterFrameScrollFrame"]

        scrollChild = scrollChild or (scrollFrame and scrollFrame.ScrollChild) or _G["KRTLootCounterFrameScrollFrameScrollChild"]

        return true
    end

    local function ensureHeader()
        if header or not scrollChild then
            return
        end

        header = CreateFrame("Frame", nil, scrollChild)
        header:SetHeight(HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)

        -- Column labels: Player | Count | (blank actions column)
        -- Layout: actions anchored hard-right, count just to its left, name fills remaining space.
        header.action = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.action:SetPoint("RIGHT", header, "RIGHT", -2, 0)
        header.action:SetWidth(ACTION_COL_W)
        header.action:SetJustifyH("RIGHT")
        header.action:SetText("")

        header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.count:SetPoint("RIGHT", header.action, "LEFT", -COL_GAP, 0)
        header.count:SetWidth(COUNT_COL_W)
        header.count:SetJustifyH("CENTER")
        header.count:SetText(L.StrCount)
        header.count:SetTextColor(0.5, 0.5, 0.5)

        header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.name:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.name:SetPoint("RIGHT", header.count, "LEFT", -COL_GAP, 0)
        header.name:SetJustifyH("LEFT")
        header.name:SetText(L.StrPlayer)
        header.name:SetTextColor(0.5, 0.5, 0.5)
    end

    local function getCurrentRaidPlayers()
        twipe(raidPlayers)
        if not addon.Core.GetCurrentRaid() then
            return raidPlayers
        end
        return Services.Raid:GetLootCounterRows(addon.Core.GetCurrentRaid(), raidPlayers)
    end

    local function ensureRow(i, rowHeight)
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(rowHeight)

            -- Actions container: hard-right, next to the scrollbar.
            row.actions = CreateFrame("Frame", nil, row)
            row.actions:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            row.actions:SetSize(ACTION_COL_W, rowHeight)

            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.count:SetPoint("RIGHT", row.actions, "LEFT", -COL_GAP, 0)
            row.count:SetWidth(COUNT_COL_W)
            row.count:SetJustifyH("CENTER")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.name:SetPoint("RIGHT", row.count, "LEFT", -COL_GAP, 0)
            row.name:SetJustifyH("LEFT")

            local function setupTooltip(btn, text)
                if not text or text == "" then
                    return
                end
                btn:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(text, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                btn:HookScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            local function makeBtn(label, tip)
                local b = CreateFrame("Button", nil, row.actions, "KRTButtonTemplate")
                b:SetSize(BTN_W, BTN_H)
                b:SetText(label)
                setupTooltip(b, tip)
                return b
            end

            row.reset = makeBtn("R", L.TipLootCounterReset)
            row.minus = makeBtn("-", L.TipLootCounterMinus)
            row.plus = makeBtn("+", L.TipLootCounterPlus)

            row.reset:SetPoint("RIGHT", row.actions, "RIGHT", 0, 0)
            row.minus:SetPoint("RIGHT", row.reset, "LEFT", -BTN_GAP, 0)
            row.plus:SetPoint("RIGHT", row.minus, "LEFT", -BTN_GAP, 0)

            row.plus:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    Services.Raid:AddPlayerCountByNid(playerNid, 1, addon.Core.GetCurrentRaid())
                    module:RequestRefresh("count_changed")
                end
            end)
            row.minus:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    Services.Raid:AddPlayerCountByNid(playerNid, -1, addon.Core.GetCurrentRaid())
                    module:RequestRefresh("count_changed")
                end
            end)
            row.reset:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    Services.Raid:SetPlayerCountByNid(playerNid, 0, addon.Core.GetCurrentRaid())
                    module:RequestRefresh("count_reset")
                end
            end)

            rows[i] = row
        end
        return row
    end

    -- ----- Public methods ----- --
    function module:OnLoad(frame)
        local f = frame or getFrame()
        UI.FrameName = Frames.InitModuleFrame(module, f, { enableDrag = true }) or UI.FrameName
        if not ensureFrames() then
            return
        end
    end

    function module:AttachToMaster(masterFrame)
        local frame = masterFrame
        if not frame or frame._krtAttached then
            return
        end

        frame._krtAttached = true
        frame:HookScript("OnHide", function()
            module:Hide()
        end)
    end

    function module:AnnounceCounts()
        local ok, reason = canBroadcastCounter()
        if not ok then
            warnBroadcastDenied(reason)
            return
        end

        local players = getCurrentRaidPlayers()
        local groupedByCount, counts = collectAnnounceGroups(players)
        if #counts <= 0 then
            addon:Announce(L.StrLootCounterAnnounceNone, "RAID")
            return
        end

        addon:Announce(L.StrLootCounterAnnounceHeader, "RAID")
        local outLines = {}
        for i = 1, #counts do
            local count = counts[i]
            appendBucketLines(outLines, count, groupedByCount[count])
        end
        for i = 1, #outLines do
            addon:Announce(outLines[i], "RAID")
        end
    end

    function module:ResetAllCounts()
        local currentRaid = addon.Core.GetCurrentRaid()
        if not currentRaid then
            return
        end

        local players = getCurrentRaidPlayers()
        local changed = false
        for i = 1, #players do
            local data = players[i]
            local playerNid = data and tonumber(data.playerNid)
            local count = (data and tonumber(data.count)) or 0
            if playerNid and count ~= 0 then
                Services.Raid:SetPlayerCountByNid(playerNid, 0, currentRaid)
                changed = true
            end
        end
        if changed then
            module:RequestRefresh("count_reset_all")
        end
    end

    function module:ConfirmResetAllCounts()
        if not ensureResetAllPopup() or type(StaticPopup_Show) ~= "function" then
            module:ResetAllCounts()
            return
        end
        StaticPopup_Show(RESET_ALL_POPUP_KEY)
    end

    function module:RefreshUI()
        if not ensureFrames() then
            return
        end
        local frame = getFrame()
        if not frame or not scrollFrame or not scrollChild then
            return
        end

        ensureHeader()

        local players = getCurrentRaidPlayers()
        local numPlayers = #players
        local rowHeight = C.LOOT_COUNTER_ROW_HEIGHT

        local contentHeight = HEADER_HEIGHT + (numPlayers * rowHeight)
        local priorScroll = scrollFrame:GetVerticalScroll() or 0

        -- Ensure the scroll child has a valid size (UIPanelScrollFrameTemplate needs this)
        local contentW = scrollFrame:GetWidth() or 0
        local sb = scrollFrame.ScrollBar or (scrollFrame.GetName and _G[scrollFrame:GetName() .. "ScrollBar"]) or nil
        local sbw = (sb and sb.GetWidth and sb:GetWidth()) or 16
        if sbw <= 0 then
            sbw = 16
        end
        contentW = math.max(1, contentW - sbw - 6)
        scrollChild:SetWidth(contentW)
        scrollChild:SetHeight(math.max(contentHeight, scrollFrame:GetHeight()))
        local maxScroll = contentHeight - scrollFrame:GetHeight()
        if maxScroll < 0 then
            maxScroll = 0
        end
        if priorScroll > maxScroll then
            priorScroll = maxScroll
        end
        scrollFrame:SetVerticalScroll(priorScroll)
        if header then
            header:Show()
        end

        local hasAnyCount = false
        for i = 1, numPlayers do
            local data = players[i]
            local name = data and data.name
            local playerNid = data and tonumber(data.playerNid)

            local row = ensureRow(i, rowHeight)
            row:ClearAllPoints()
            local y = -(HEADER_HEIGHT + (i - 1) * rowHeight)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, y)
            row._playerNid = playerNid

            if row._lastName ~= name then
                row.name:SetText(name)
                row._lastName = name
            end

            local class = data and data.class or Services.Raid:GetPlayerClass(name)
            if row._lastClass ~= class then
                local r, g, b = Colors.GetClassColor(class)
                row.name:SetTextColor(r, g, b)
                row._lastClass = class
            end

            local cnt = (data and tonumber(data.count)) or (playerNid and Services.Raid:GetPlayerCountByNid(playerNid, addon.Core.GetCurrentRaid())) or 0
            if row._lastCount ~= cnt then
                row.count:SetText(tostring(cnt))
                row._lastCount = cnt
            end
            if cnt > 0 then
                hasAnyCount = true
            end
            row:Show()
        end

        for i = numPlayers + 1, #rows do
            if rows[i] then
                rows[i]:Hide()
            end
        end

        local announceBtn = getAnnounceButton()
        if announceBtn then
            local canBroadcast = canBroadcastCounter()
            if canBroadcast then
                announceBtn:Enable()
            else
                announceBtn:Disable()
            end
        end

        local resetAllBtn = getResetAllButton()
        if resetAllBtn then
            if numPlayers > 0 and hasAnyCount then
                resetAllBtn:Enable()
            else
                resetAllBtn:Disable()
            end
        end
    end

    function module:Refresh()
        return self:RefreshUI()
    end

    local function BindHandlers(_, _, refs)
        scrollFrame = refs.scrollFrame or scrollFrame
        scrollChild = refs.scrollChild or scrollChild
        Frames.SafeSetScript(refs.announceBtn, "OnClick", function()
            module:AnnounceCounts()
        end)
        Frames.SafeSetScript(refs.resetAllBtn, "OnClick", function()
            module:ConfirmResetAllCounts()
        end)
    end

    local function OnLoadFrame(frame)
        module:OnLoad(frame)
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
    })

    local function requestRefresh()
        -- Coalesced, event-driven refresh (safe even if frame is hidden/not yet created).
        module:RequestRefresh()
    end

    -- Refresh on roster updates (to keep list aligned).
    Bus.RegisterCallback(InternalEvents.RaidRosterDelta, requestRefresh)

    -- Refresh when counts actually change (MS loot award or manual +/-/reset).
    Bus.RegisterCallback(InternalEvents.PlayerCountChanged, requestRefresh)

    -- New raid session: reset view.
    Bus.RegisterCallback(InternalEvents.RaidCreate, requestRefresh)

    if UIFacade and UIFacade.Register then
        UIFacade:Register(
            "LootCounter",
            UIScaffold.MakeStandardWidgetApi(module, {
                AttachToMaster = function(masterFrame)
                    module:AttachToMaster(masterFrame)
                end,
            })
        )
    end
end
