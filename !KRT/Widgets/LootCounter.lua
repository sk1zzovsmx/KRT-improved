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
local Events = feature.Events or addon.Events or {}
local C = feature.C
local Bus = feature.Bus or addon.Bus

local bindModuleRequestRefresh = feature.BindModuleRequestRefresh
local bindModuleToggleHide = feature.BindModuleToggleHide
local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local twipe = table.wipe

local type, tostring = type, tostring

local InternalEvents = Events.Internal
local UI = addon.UI

local function isWidgetEnabled(widgetId)
    if UI and type(UI.IsEnabled) == "function" then
        return UI:IsEnabled(widgetId)
    end
    return true
end

-- Loot counter module.
-- Tracks and edits item distribution counts (MS wins).
do
    if not isWidgetEnabled("LootCounter") then
        return
    end

    addon.Widgets = addon.Widgets or {}
    addon.Widgets.LootCounter = addon.Widgets.LootCounter or addon.LootCounter or {}
    addon.LootCounter = addon.Widgets.LootCounter -- Legacy alias during namespacing migration.
    local module = addon.Widgets.LootCounter

    -- ----- Internal state ----- --
    local frameName
    local rows, raidPlayers = {}, {}
    local scrollFrame, scrollChild, header
    local getFrame = makeModuleFrameGetter(module, "KRTLootCounterFrame")
    local uiBound = false
    local scaffoldToggle, scaffoldHide

    -- Single-line column header.
    local HEADER_HEIGHT = 18

    -- Layout constants (columns: Name | Count | Actions)
    local BTN_W, BTN_H = 20, 18
    local BTN_GAP = 2
    local COL_GAP = 8
    local ACTION_COL_W = (BTN_W * 3) + (BTN_GAP * 2) + 2 -- (+/-/R + gaps + right pad)
    local COUNT_COL_W = 40

    -- ----- Private helpers ----- --
    local function AcquireRefs(frame)
        local refs = {
            scrollFrame = frame
                and (frame.ScrollFrame or _G[(frame.GetName and frame:GetName() or "KRTLootCounterFrame") .. "ScrollFrame"])
                or nil,
        }
        refs.scrollChild = (refs.scrollFrame and refs.scrollFrame.ScrollChild)
            or _G["KRTLootCounterFrameScrollFrameScrollChild"]
        return refs
    end

    local function ensureFrames()
        local frame = getFrame()
        if not frame then
            return false
        end

        frameName = frameName or (frame.GetName and frame:GetName()) or "KRTLootCounterFrame"
        scrollFrame = scrollFrame
            or frame.ScrollFrame
            or _G[frameName .. "ScrollFrame"]
            or _G["KRTLootCounterFrameScrollFrame"]

        scrollChild = scrollChild
            or (scrollFrame and scrollFrame.ScrollChild)
            or _G["KRTLootCounterFrameScrollFrameScrollChild"]

        if not frame._krtInitialized then
            Frames.SetFrameTitle(frameName, L.StrLootCounter)
            frame._krtInitialized = true
        end

        return true
    end

    local function ensureHeader()
        if header or not scrollChild then return end

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
        return addon.Raid:GetLootCounterRows(addon.Core.GetCurrentRaid(), raidPlayers)
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
                if not text or text == "" then return end
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
            row.plus  = makeBtn("+", L.TipLootCounterPlus)

            row.reset:SetPoint("RIGHT", row.actions, "RIGHT", 0, 0)
            row.minus:SetPoint("RIGHT", row.reset, "LEFT", -BTN_GAP, 0)
            row.plus:SetPoint("RIGHT", row.minus, "LEFT", -BTN_GAP, 0)

            row.plus:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    addon.Raid:AddPlayerCountByNid(playerNid, 1, addon.Core.GetCurrentRaid())
                    module:RequestRefresh()
                end
            end)
            row.minus:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    addon.Raid:AddPlayerCountByNid(playerNid, -1, addon.Core.GetCurrentRaid())
                    module:RequestRefresh()
                end
            end)
            row.reset:SetScript("OnClick", function()
                local playerNid = row._playerNid
                if playerNid then
                    addon.Raid:SetPlayerCountByNid(playerNid, 0, addon.Core.GetCurrentRaid())
                    module:RequestRefresh()
                end
            end)

            rows[i] = row
        end
        return row
    end

    -- ----- Public methods ----- --
    function module:OnLoad(frame)
        local f = frame or getFrame()
        frameName = Frames.InitModuleFrame(module, f, { enableDrag = true }) or frameName
        if not ensureFrames() then return end
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

    function module:Refresh()
        if not ensureFrames() then return end
        local frame = getFrame()
        if not frame or not scrollFrame or not scrollChild then return end

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
        if sbw <= 0 then sbw = 16 end
        contentW = math.max(1, contentW - sbw - 6)
        scrollChild:SetWidth(contentW)
        scrollChild:SetHeight(math.max(contentHeight, scrollFrame:GetHeight()))
        local maxScroll = contentHeight - scrollFrame:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        if priorScroll > maxScroll then
            priorScroll = maxScroll
        end
        scrollFrame:SetVerticalScroll(priorScroll)
        if header then header:Show() end

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

            local class = data and data.class or addon.Raid:GetPlayerClass(name)
            if row._lastClass ~= class then
                local r, g, b = Colors.GetClassColor(class)
                row.name:SetTextColor(r, g, b)
                row._lastClass = class
            end

            local cnt = (data and tonumber(data.count))
                or (playerNid and addon.Raid:GetPlayerCountByNid(playerNid, addon.Core.GetCurrentRaid()))
                or 0
            if row._lastCount ~= cnt then
                row.count:SetText(tostring(cnt))
                row._lastCount = cnt
            end
            row:Show()
        end

        for i = numPlayers + 1, #rows do
            if rows[i] then rows[i]:Hide() end
        end
    end

    -- UI window management.

    -- Initialize UI controller for Toggle/Hide.
    UIScaffold.BootstrapModuleUi(module, getFrame, function() module:RequestRefresh() end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    scaffoldToggle = module.Toggle
    scaffoldHide = module.Hide

    function module:BindUI()
        if uiBound and self.frame and self.refs then
            return self.frame, self.refs
        end

        local frame = getFrame()
        if not frame then
            return nil
        end
        if not frameName then
            self:OnLoad(frame)
        end

        local refs = AcquireRefs(frame)
        self.frame = frame
        self.refs = refs

        scrollFrame = refs.scrollFrame or scrollFrame
        scrollChild = refs.scrollChild or scrollChild

        uiBound = true
        return frame, refs
    end

    function module:EnsureUI()
        if uiBound and self.frame and self.refs then
            return self.frame
        end
        return self:BindUI()
    end

    function module:Toggle()
        if not self:EnsureUI() then
            return
        end
        if scaffoldToggle then
            return scaffoldToggle(self)
        end
    end

    function module:Hide()
        if not self:EnsureUI() then
            return
        end
        if scaffoldHide then
            return scaffoldHide(self)
        end
    end

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

    if addon.UI and addon.UI.Register then
        addon.UI:Register("LootCounter", {
            Toggle = function()
                if module.Toggle then
                    module:Toggle()
                end
            end,
            Hide = function()
                if module.Hide then
                    module:Hide()
                end
            end,
            AttachToMaster = function(masterFrame)
                module:AttachToMaster(masterFrame)
            end,
        })
    end
end

