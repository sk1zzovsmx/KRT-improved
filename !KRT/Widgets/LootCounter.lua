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
local Chat = Services.Chat
local Raid = Services.Raid

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
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui

    -- ----- Internal state ----- --
    local rows, raidPlayers = {}, {}
    local scrollFrame, scrollChild, header
    local getFrame = makeModuleFrameGetter(module, "KRTLootCounterFrame")

    -- Single-line column header.
    local HEADER_HEIGHT = 20

    -- Layout constants (columns: Name | MS | OS | FREE | R)
    local BTN_W, BTN_H = 18, 18
    local BTN_GAP = 2 -- gap between +/- buttons within a section
    local SECTION_GAP = 8 -- gap between MS/OS/FREE section containers (separator lives in the center)
    local COL_GAP = 6 -- gap between name and first section
    local COUNT_LABEL_W = 22 -- width of the numeric count display
    local RESET_BTN_W = 18 -- per-row reset button
    local RESET_BTN_GAP = 16 -- wide gap between FREE section and reset button (avoids accidental clicks)
    local RIGHT_EDGE = -2 -- offset from scrollChild right for the reset button

    -- One section = count label + gap + minus button + gap + plus button
    local SECTION_W = COUNT_LABEL_W + BTN_GAP + BTN_W + BTN_GAP + BTN_W -- 62

    local CHAT_MSG_MAX_LEN = 255
    local RESET_ALL_POPUP_KEY = "KRT_LOOTCOUNTER_RESET_ALL"
    local SOLID_TEX = "Interface\\Buttons\\WHITE8x8"

    local COLOR_HEADER_TEXT = { 0.88, 0.88, 0.88 }
    local COLOR_ROW_BG_ODD = { 1, 1, 1, 0.06 }
    local COLOR_ROW_BG_EVEN = { 1, 1, 1, 0.03 }
    local COLOR_ROW_BG_ACTIVE = { 0.95, 0.74, 0.23, 0.13 }
    local COLOR_ROW_SEPARATOR = { 1, 1, 1, 0.06 }
    local COLOR_SEPARATOR = { 1, 1, 1, 0.20 }
    local COLOR_COUNT_ZERO = { 0.56, 0.56, 0.56 }
    local COLOR_COUNT_MS = { 0.96, 0.82, 0.32 }
    local COLOR_COUNT_OS = { 0.63, 0.80, 1.00 }
    local COLOR_COUNT_FREE = { 0.70, 0.98, 0.72 }

    local function setTextureColor(tex, rgba)
        if not (tex and rgba) then
            return
        end
        tex:SetTexture(SOLID_TEX)
        tex:SetVertexColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end

    local function setFontColor(fs, rgb)
        if not (fs and rgb) then
            return
        end
        fs:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
    end

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
        local raidService = Raid
        if not (raidService and raidService.IsPlayerInRaid and raidService:IsPlayerInRaid()) then
            return false, "not_in_raid"
        end

        if type(raidService.GetCapabilityState) == "function" then
            local state = raidService:GetCapabilityState("changes_broadcast")
            if state and state.allowed == true then
                return true
            end
            return false, state and state.reason or "missing_leadership"
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

    local function announceToRaid(text)
        if Chat and Chat.Announce then
            Chat:Announce(text, "RAID")
        end
    end

    local function collectAnnounceGroups(players, countField)
        local groupedByCount = {}
        local counts = {}

        for i = 1, #players do
            local row = players[i]
            local name = row and row.name
            local count = (row and tonumber(row[countField])) or 0
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

    local function announceCountSection(players, countField, sectionHeader, noneMsg)
        local groupedByCount, counts = collectAnnounceGroups(players, countField)
        if #counts <= 0 then
            announceToRaid(noneMsg)
            return
        end
        announceToRaid(sectionHeader)
        local outLines = {}
        for i = 1, #counts do
            appendBucketLines(outLines, counts[i], groupedByCount[counts[i]])
        end
        for i = 1, #outLines do
            announceToRaid(outLines[i])
        end
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

    -- Draws a 1px vertical separator centered in the gap to the LEFT of anchorRef.
    local function addColumnSeparator(parent, anchorRef, topInset, bottomInset)
        local tex = parent:CreateTexture(nil, "BACKGROUND")
        tex:SetWidth(1)
        tex:SetPoint("TOP", anchorRef, "TOPLEFT", -SECTION_GAP / 2, -topInset)
        tex:SetPoint("BOTTOM", anchorRef, "BOTTOMLEFT", -SECTION_GAP / 2, bottomInset)
        setTextureColor(tex, COLOR_SEPARATOR)
    end

    local function makeHeaderLabel(parent, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetWidth(SECTION_W)
        fs:SetJustifyH("CENTER")
        fs:SetText(text)
        setFontColor(fs, COLOR_HEADER_TEXT)
        return fs
    end

    local function ensureHeader()
        if header or not scrollChild then
            return
        end

        header = CreateFrame("Frame", nil, scrollChild)
        header:SetHeight(HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
        header.separator = header:CreateTexture(nil, "BORDER")
        header.separator:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        header.separator:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        header.separator:SetHeight(1)
        setTextureColor(header.separator, COLOR_ROW_SEPARATOR)

        -- Anchor from right: [reset placeholder] [FREE] [OS] [MS] [Name fills left]
        header.resetPlaceholder = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.resetPlaceholder:SetWidth(RESET_BTN_W)
        header.resetPlaceholder:SetPoint("RIGHT", header, "RIGHT", RIGHT_EDGE, 0)
        header.resetPlaceholder:SetText("R")
        setFontColor(header.resetPlaceholder, COLOR_HEADER_TEXT)

        header.freeLabel = makeHeaderLabel(header, L.StrFREE)
        header.freeLabel:SetPoint("RIGHT", header.resetPlaceholder, "LEFT", -RESET_BTN_GAP, 0)
        setFontColor(header.freeLabel, COLOR_COUNT_FREE)

        header.osLabel = makeHeaderLabel(header, L.StrOS)
        header.osLabel:SetPoint("RIGHT", header.freeLabel, "LEFT", -SECTION_GAP, 0)
        setFontColor(header.osLabel, COLOR_COUNT_OS)

        header.msLabel = makeHeaderLabel(header, L.StrMS)
        header.msLabel:SetPoint("RIGHT", header.osLabel, "LEFT", -SECTION_GAP, 0)
        setFontColor(header.msLabel, COLOR_COUNT_MS)

        -- Vertical separators centered in the gaps between column labels and before reset column.
        addColumnSeparator(header, header.osLabel, 3, 3)
        addColumnSeparator(header, header.freeLabel, 3, 3)
        addColumnSeparator(header, header.resetPlaceholder, 3, 3)

        header.name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.name:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.name:SetPoint("RIGHT", header.msLabel, "LEFT", -COL_GAP, 0)
        header.name:SetJustifyH("LEFT")
        header.name:SetText(L.StrPlayer)
        setFontColor(header.name, COLOR_HEADER_TEXT)
    end

    local function applyCountLabelColor(fs, count, positiveColor)
        if not fs then
            return
        end
        if (tonumber(count) or 0) > 0 then
            setFontColor(fs, positiveColor)
            return
        end
        setFontColor(fs, COLOR_COUNT_ZERO)
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

            local function makeBtn(parent, label, tip)
                local b = CreateFrame("Button", nil, parent, "KRTButtonTemplate")
                b:SetSize(BTN_W, BTN_H)
                b:SetText(label)
                local txt = b:GetFontString()
                if txt then
                    txt:ClearAllPoints()
                    txt:SetPoint("CENTER", b, "CENTER", 0, 0)
                end
                setupTooltip(b, tip)
                return b
            end

            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints(row)
            setTextureColor(row.background, COLOR_ROW_BG_ODD)

            row.separator = row:CreateTexture(nil, "BORDER")
            row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.separator:SetHeight(1)
            setTextureColor(row.separator, COLOR_ROW_SEPARATOR)

            -- Per-row reset: resets all three counts for this player.
            row.reset = makeBtn(row, "R", L.TipLootCounterReset)
            row.reset:SetSize(RESET_BTN_W, BTN_H)
            row.reset:SetPoint("RIGHT", row, "RIGHT", RIGHT_EDGE, 0)

            -- Build one section container per loot type (FREE → OS → MS, right to left).
            local function makeSection(anchorRight, anchorOffset)
                local sec = CreateFrame("Frame", nil, row)
                sec:SetSize(SECTION_W, rowHeight)
                sec:SetPoint("RIGHT", anchorRight, "LEFT", anchorOffset, 0)

                sec.plus = makeBtn(sec, "+", L.TipLootCounterPlus)
                sec.minus = makeBtn(sec, "-", L.TipLootCounterMinus)
                sec.count = sec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                sec.count:SetWidth(COUNT_LABEL_W)
                sec.count:SetJustifyH("CENTER")

                -- Inside section from right: [+(16)] [gap] [-(16)] [gap] [count(20)]
                sec.plus:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
                sec.minus:SetPoint("RIGHT", sec.plus, "LEFT", -BTN_GAP, 0)
                sec.count:SetPoint("RIGHT", sec.minus, "LEFT", -BTN_GAP, 0)

                return sec
            end

            row.freeSection = makeSection(row.reset, -RESET_BTN_GAP)
            row.osSection = makeSection(row.freeSection, -SECTION_GAP)
            row.msSection = makeSection(row.osSection, -SECTION_GAP)

            -- Vertical separators between sections and before the reset button.
            addColumnSeparator(row, row.osSection, 2, 2)
            addColumnSeparator(row, row.freeSection, 2, 2)
            addColumnSeparator(row, row.reset, 2, 2)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.name:SetPoint("RIGHT", row.msSection, "LEFT", -COL_GAP, 0)
            row.name:SetJustifyH("LEFT")

            -- Button click handlers.
            local LOOT_TYPES = { ms = row.msSection, os = row.osSection, free = row.freeSection }
            for lootType, sec in pairs(LOOT_TYPES) do
                local lt = lootType
                sec.plus:SetScript("OnClick", function()
                    local nid = row._playerNid
                    if nid then
                        Services.Raid:AddPlayerLootCountByNid(nid, lt, 1, addon.Core.GetCurrentRaid())
                        module:RequestRefresh("count_changed")
                    end
                end)
                sec.minus:SetScript("OnClick", function()
                    local nid = row._playerNid
                    if nid then
                        Services.Raid:AddPlayerLootCountByNid(nid, lt, -1, addon.Core.GetCurrentRaid())
                        module:RequestRefresh("count_changed")
                    end
                end)
            end

            row.reset:SetScript("OnClick", function()
                local nid = row._playerNid
                if nid then
                    local raidNum = addon.Core.GetCurrentRaid()
                    Services.Raid:SetPlayerLootCountByNid(nid, "ms", 0, raidNum)
                    Services.Raid:SetPlayerLootCountByNid(nid, "os", 0, raidNum)
                    Services.Raid:SetPlayerLootCountByNid(nid, "free", 0, raidNum)
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
        announceCountSection(players, "msCount", L.StrLootCounterAnnounceHeader, L.StrLootCounterAnnounceNone)
        announceCountSection(players, "osCount", L.StrLootCounterAnnounceHeaderOs, L.StrLootCounterAnnounceNoneOs)
        announceCountSection(players, "freeCount", L.StrLootCounterAnnounceHeaderFree, L.StrLootCounterAnnounceNoneFree)
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
            if playerNid then
                local ms = (data and tonumber(data.msCount)) or 0
                local os = (data and tonumber(data.osCount)) or 0
                local free = (data and tonumber(data.freeCount)) or 0
                if ms ~= 0 or os ~= 0 or free ~= 0 then
                    Services.Raid:SetPlayerLootCountByNid(playerNid, "ms", 0, currentRaid)
                    Services.Raid:SetPlayerLootCountByNid(playerNid, "os", 0, currentRaid)
                    Services.Raid:SetPlayerLootCountByNid(playerNid, "free", 0, currentRaid)
                    changed = true
                end
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
        local frameHeight = scrollFrame:GetHeight() or 0
        local maxScroll = contentHeight - frameHeight
        if maxScroll < 0 then
            maxScroll = 0
        end

        -- Ensure the scroll child has a valid size (UIPanelScrollFrameTemplate needs this)
        local sb = scrollFrame.ScrollBar or (scrollFrame.GetName and _G[scrollFrame:GetName() .. "ScrollBar"]) or nil
        local needsScroll = maxScroll > 0
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        if needsScroll and sb and sb.IsShown and sb:IsShown() then
            scrollChild:SetPoint("TOPRIGHT", sb, "TOPLEFT", 0, 0)
        else
            scrollChild:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, 0)
        end
        scrollChild:SetHeight(math.max(contentHeight, frameHeight))
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

            local msCount = (data and tonumber(data.msCount)) or 0
            local osCount = (data and tonumber(data.osCount)) or 0
            local freeCount = (data and tonumber(data.freeCount)) or 0

            if row._lastMsCount ~= msCount then
                row.msSection.count:SetText(tostring(msCount))
                row._lastMsCount = msCount
            end
            if row._lastOsCount ~= osCount then
                row.osSection.count:SetText(tostring(osCount))
                row._lastOsCount = osCount
            end
            if row._lastFreeCount ~= freeCount then
                row.freeSection.count:SetText(tostring(freeCount))
                row._lastFreeCount = freeCount
            end
            local rowHasCount = msCount > 0 or osCount > 0 or freeCount > 0
            if rowHasCount then
                hasAnyCount = true
            end

            local rowStyle = COLOR_ROW_BG_ODD
            if i % 2 == 0 then
                rowStyle = COLOR_ROW_BG_EVEN
            end
            if rowHasCount then
                rowStyle = COLOR_ROW_BG_ACTIVE
            end
            setTextureColor(row.background, rowStyle)

            applyCountLabelColor(row.msSection.count, msCount, COLOR_COUNT_MS)
            applyCountLabelColor(row.osSection.count, osCount, COLOR_COUNT_OS)
            applyCountLabelColor(row.freeSection.count, freeCount, COLOR_COUNT_FREE)

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
