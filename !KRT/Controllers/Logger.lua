-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Frames = feature.Frames or addon.Frames
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events or addon.Events
local C = feature.C
local Core = feature.Core
local Options = feature.Options or addon.Options
local Bus = feature.Bus or addon.Bus
local ListController = feature.ListController or addon.ListController
local MultiSelect = feature.MultiSelect or addon.MultiSelect
local Strings = feature.Strings or addon.Strings
local Colors = feature.Colors or addon.Colors
local Base64 = feature.Base64 or addon.Base64
local Sort = feature.Sort or addon.Sort
local Services = feature.Services or addon.Services

local CompareValues = Sort.CompareValues
local CompareNumbers = Sort.CompareNumbers
local CompareStrings = Sort.CompareStrings
local GetLootSortName = Sort.GetLootSortName
local CompareLootTie = Sort.CompareLootTie

local InternalEvents = Events.Internal

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local rollTypes = feature.rollTypes
local lootTypesColored = feature.lootTypesColored
local itemColors = feature.itemColors
local showLoggerExportFrame

local _G = _G
local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber
local strlower = string.lower

local LEGACY_TRASH_MOB_NAME = "_TrashMob_"
local function resolveTrashMobName()
    local localizedName = L and L.StrTrashMobName
    if type(localizedName) ~= "string" or localizedName == "" then
        return LEGACY_TRASH_MOB_NAME
    end
    if localizedName == "StrTrashMobName" or localizedName == "L.StrTrashMobName" then
        return LEGACY_TRASH_MOB_NAME
    end
    return localizedName
end

local TRASH_MOB_NAME = resolveTrashMobName()

local loggerPanelNames = {
    "KRTLoggerRaids",
    "KRTLoggerBosses",
    "KRTLoggerBossAttendees",
    "KRTLoggerRaidAttendees",
    "KRTLoggerLoot",
}

local loggerHeaderSuffixes = {
    "HeaderNum",
    "HeaderDate",
    "HeaderZone",
    "HeaderSize",
    "HeaderName",
    "HeaderTime",
    "HeaderMode",
    "HeaderJoin",
    "HeaderLeave",
    "HeaderItem",
    "HeaderSource",
    "HeaderWinner",
    "HeaderType",
    "HeaderRoll",
}

local function styleLoggerHeader(header)
    if not header then
        return
    end

    local text = header.GetFontString and header:GetFontString() or nil
    if text and text.SetTextColor then
        text:SetTextColor(0.95, 0.95, 0.95)
    end
end

local function styleLoggerPanel(frameName)
    local frame = frameName and _G[frameName] or nil
    if not frame then
        return
    end

    if frame.SetBackdropColor then
        frame:SetBackdropColor(0.01, 0.01, 0.01, 0.82)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(0.48, 0.48, 0.48, 0.92)
    end

    local title = _G[frameName .. "Title"]
    if title then
        title:SetTextColor(1.00, 0.82, 0.00)
        title:SetJustifyH("LEFT")
    end

    for i = 1, #loggerHeaderSuffixes do
        styleLoggerHeader(_G[frameName .. loggerHeaderSuffixes[i]])
    end
end

local function applyLoggerSkin()
    for i = 1, #loggerPanelNames do
        styleLoggerPanel(loggerPanelNames[i])
    end
end

local function styleLoggerRow(row)
    if not row then
        return
    end

    row._krtRowVisualStyle = "logger"
    if not row._krtLoggerBg then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:SetTexture(0.01, 0.01, 0.01, 0.58)
        row._krtLoggerBg = bg

        local line = row:CreateTexture(nil, "BORDER")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
        line:SetTexture(0.35, 0.35, 0.35, 0.30)
        row._krtLoggerLine = line
    end
end

local SetSelectedRaid
local deleteSelectedAttendees
local setFrameLabel
local setPanelTitle
local getSelectedRaidRecord
local setFrameHint
local needRaid
local needBoss
local needLoot
local runWithSelectedRaid
local resetSelections
local selectRaid
local selectBoss
local selectBossPlayer
local selectPlayer
local selectItem
local onLootRowEnter
local onLootRowLeave
local fillBossBox
local function isTrashMobName(name)
    return name == TRASH_MOB_NAME or name == LEGACY_TRASH_MOB_NAME
end

local selectionEvents = {
    selectedRaid = InternalEvents.LoggerSelectRaid,
    selectedBoss = InternalEvents.LoggerSelectBoss,
    selectedPlayer = InternalEvents.LoggerSelectPlayer,
    selectedBossPlayer = InternalEvents.LoggerSelectBossPlayer,
    selectedItem = InternalEvents.LoggerSelectItem,
}

local function triggerSelectionEvent(target, key, ...)
    local eventName = selectionEvents[key]
    if not eventName then
        return
    end
    Bus.TriggerEvent(eventName, target[key], ...)
end

local RAID_SORT_HEADERS = {
    { suffix = "HeaderNum", key = "id" },
    { suffix = "HeaderDate", key = "date" },
    { suffix = "HeaderZone", key = "zone" },
    { suffix = "HeaderSize", key = "size" },
}

local function bindRaidSortHeaders(frameName, listRef)
    local frame = frameName and _G[frameName] or nil
    if not frame or frame._krtBound then
        return
    end

    for i = 1, #RAID_SORT_HEADERS do
        local header = RAID_SORT_HEADERS[i]
        local sortKey = header.key
        local headerButton = _G[frameName .. header.suffix]
        if headerButton then
            Frames.SafeSetScript(headerButton, "OnClick", function()
                listRef:Sort(sortKey)
            end)
        end
    end

    frame._krtBound = true
end

local function buildRaidListRow(raid, seq, queries)
    if not raid then
        return nil
    end

    local summary = queries and queries.GetRaidSummary and queries:GetRaidSummary(raid) or nil
    local row = {}
    row.id = tonumber(raid.raidNid)
    row.seq = seq
    row.zone = raid.zone
    row.size = (summary and summary.size) or raid.size
    row.difficulty = tonumber((summary and summary.difficulty) or raid.difficulty)
    local mode = row.difficulty and ((row.difficulty == 3 or row.difficulty == 4) and "H" or "N") or "?"
    row.sizeLabel = tostring(row.size or "") .. mode
    row.date = (summary and summary.startTime) or raid.startTime
    row.dateFmt = date("%d/%m/%Y %H:%M", row.date)
    return row
end

local function fillRaidListData(out, contextTag)
    local raidStore = Core.GetRaidStoreOrNil(contextTag, { "GetAllRaids", "GetRaidByIndex" })
    local raids = raidStore and raidStore:GetAllRaids() or {}
    local queries = Core.GetRaidQueries and Core.GetRaidQueries() or nil
    for i = 1, #raids do
        local raid = raidStore and raidStore:GetRaidByIndex(i) or Core.EnsureRaidById(i)
        local row = buildRaidListRow(raid, i, queries)
        if row then
            out[i] = row
        end
    end
end

addon.Controllers.Logger = addon.Controllers.Logger or {}
local module = addon.Controllers.Logger
module._ui = UIScaffold.EnsureModuleUi(module)

-- Logger frame module.
do
    -- ----- Internal state ----- --
    local UI = module._ui
    local getFrame = makeModuleFrameGetter(module, "KRTLogger")
    -- Import service modules (extracted to Services/Logger/).
    local LoggerSvc = addon.Services.Logger
    local Store = LoggerSvc.Store
    local View = LoggerSvc.View
    local Export = LoggerSvc.Export
    local Actions = LoggerSvc.Actions
    local Helpers = LoggerSvc.Helpers

    module.Store = Store
    module.View = View
    module.Export = Export
    module.Actions = Actions
    module.Helpers = Helpers

    -- Bind controller reference so Logger actions can validate selections.
    Actions:BindController(module, triggerSelectionEvent)

    -- ----- Private helpers ----- --

    function UI.AcquireRefs(frame)
        return {
            historyTabBtn = Frames.Ref(frame, "Tab1"),
            history = Frames.Ref(frame, "History"),
            raids = Frames.Ref(frame, "KRTLoggerRaids"),
            bosses = Frames.Ref(frame, "KRTLoggerBosses"),
            loot = Frames.Ref(frame, "KRTLoggerLoot"),
            raidAttendees = Frames.Ref(frame, "KRTLoggerRaidAttendees"),
            bossAttendees = Frames.Ref(frame, "KRTLoggerBossAttendees"),
            bossBox = Frames.Ref(frame, "KRTLoggerBossBox"),
            attendeesBox = Frames.Ref(frame, "KRTLoggerPlayerBox"),
        }
    end

    local function ensureSubmoduleOnLoad(moduleRef, frame)
        if not (moduleRef and moduleRef.OnLoad and frame) then
            return
        end
        if frame._krtOnLoadBound then
            return
        end
        moduleRef:OnLoad(frame)
        frame._krtOnLoadBound = true
    end

    local function clearSelection(target, key, multiSelectCtx)
        target[key] = nil
        if multiSelectCtx then
            MultiSelect.MultiSelectClear(multiSelectCtx)
        end
    end

    setFrameLabel = function(frameName, suffix, text)
        local label = frameName and _G[frameName .. suffix] or nil
        if not label then
            return nil
        end
        if label.GetText and label:GetText() == text then
            return label
        end
        label:SetText(text)
        return label
    end

    setPanelTitle = function(frameName, text)
        setFrameLabel(frameName, "Title", text)
    end

    setFrameHint = function(frameName, suffix, text)
        local label = setFrameLabel(frameName, suffix, text or "")
        if label then
            UIPrimitives.ShowHide(label, type(text) == "string" and text ~= "")
        end
    end

    getSelectedRaidRecord = function()
        if not module.selectedRaid then
            return nil
        end
        return Store:GetRaid(module.selectedRaid)
    end

    local function applyFocusedMultiSelect(opts)
        if not opts then
            return nil, 0
        end

        local id = opts.id
        local ctx = opts.context
        if not (id and ctx and opts.setFocus) then
            return nil, 0
        end

        local function setFocusFromSelected(selectedId)
            if opts.mapSelectedToFocus then
                opts.setFocus(opts.mapSelectedToFocus(selectedId))
                return
            end
            opts.setFocus(selectedId)
        end

        if opts.isRange then
            local action, count = MultiSelect.MultiSelectRange(ctx, opts.ordered, id, opts.isMulti)
            setFocusFromSelected(id)
            return action, count
        end

        local allowDeselect = opts.allowDeselect
        if allowDeselect == nil then
            allowDeselect = true
        end

        local action, count = MultiSelect.MultiSelectToggle(ctx, id, opts.isMulti, allowDeselect)
        if action == "SINGLE_DESELECT" then
            opts.setFocus(nil)
        elseif action == "TOGGLE_OFF" then
            local clickedWasFocused = false
            if opts.isClickedFocused then
                clickedWasFocused = opts.isClickedFocused(id) and true or false
            elseif opts.getFocus then
                clickedWasFocused = (opts.getFocus() == id)
            end

            if clickedWasFocused then
                local selected = MultiSelect.MultiSelectGetSelected(ctx)
                setFocusFromSelected(selected[1])
            end
        else
            setFocusFromSelected(id)
        end

        if (tonumber(count) or 0) > 0 then
            MultiSelect.MultiSelectSetAnchor(ctx, id)
        else
            MultiSelect.MultiSelectSetAnchor(ctx, nil)
        end

        return action, count
    end

    -- ----- Public methods ----- --

    module.selectedRaid = nil
    module.selectedBoss = nil
    module.selectedPlayer = nil
    module.selectedBossPlayer = nil
    module.selectedItem = nil
    SetSelectedRaid = function(raidId)
        if raidId == nil then
            module.selectedRaid = nil
        else
            module.selectedRaid = tonumber(raidId) or raidId
        end
        local state = addon.State
        state.selectedRaid = module.selectedRaid
        return module.selectedRaid
    end

    -- Multi-select context keys (runtime-only)
    -- NOTE: selection state lives in MultiSelect module and is keyed by these context strings.
    module._msRaidCtx = module._msRaidCtx or "LoggerRaids"
    module._msBossCtx = module._msBossCtx or "LoggerBosses"
    module._msBossAttCtx = module._msBossAttCtx or "LoggerBossAttendees"
    module._msRaidAttCtx = module._msRaidAttCtx or "LoggerRaidAttendees"
    module._msLootCtx = module._msLootCtx or "LoggerLoot"

    local MS_CTX_RAID = module._msRaidCtx
    local MS_CTX_BOSS = module._msBossCtx
    local MS_CTX_BOSSATT = module._msBossAttCtx
    local MS_CTX_RAIDATT = module._msRaidAttCtx
    local MS_CTX_LOOT = module._msLootCtx

    -- Multi-select modifier scopes (input policy by panel/list)
    module._msRaidScopeHistory = module._msRaidScopeHistory or "LoggerRaidsHistory"
    module._msBossScope = module._msBossScope or "LoggerBosses"
    module._msBossAttScope = module._msBossAttScope or "LoggerBossAttendees"
    module._msRaidAttScope = module._msRaidAttScope or "LoggerRaidAttendees"
    module._msLootScope = module._msLootScope or "LoggerLoot"

    local MS_SCOPE_RAID_HISTORY = module._msRaidScopeHistory
    local MS_SCOPE_BOSS = module._msBossScope
    local MS_SCOPE_BOSSATT = module._msBossAttScope
    local MS_SCOPE_RAIDATT = module._msRaidAttScope
    local MS_SCOPE_LOOT = module._msLootScope

    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_RAID_HISTORY, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_BOSS, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_BOSSATT, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_RAIDATT, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_LOOT, { allowMulti = true, allowRange = true })

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        clearSelection(module, "selectedBoss", MS_CTX_BOSS)
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
        clearSelection(module, "selectedItem", MS_CTX_LOOT)
    end

    deleteSelectedAttendees = function(ctx, deleteFn, onRemoved)
        runWithSelectedRaid(function(_, rID)
            local ids = MultiSelect.MultiSelectGetSelected(ctx)
            if not (ids and #ids > 0) then
                return
            end

            local removed = deleteFn(rID, ids)
            if not removed or removed <= 0 then
                return
            end

            MultiSelect.MultiSelectClear(ctx)
            if type(onRemoved) == "function" then
                onRemoved(removed, ids)
            end
        end)
    end

    local rosterUiRefreshDebounceSeconds = 0.25

    module.IsLoggerViewingCurrentRaid = function()
        local frame = module.frame or getFrame()
        if not (frame and frame.IsShown and frame:IsShown()) then
            return false
        end
        local currentRaid = Core.GetCurrentRaid()
        return currentRaid and module.selectedRaid and tonumber(module.selectedRaid) == tonumber(currentRaid)
    end

    local function refreshRosterBoundLists()
        local listModules = { module.RaidAttendees, module.BossAttendees, module.Loot }
        for i = 1, #listModules do
            local ctrl = listModules[i] and listModules[i]._ctrl
            if ctrl and ctrl.Dirty then
                ctrl:Dirty()
            end
        end
    end

    module.RequestRosterBoundListsRefresh = function()
        addon.CancelTimer(module._rosterUiHandle, true)
        module._rosterUiHandle = addon.NewTimer(rosterUiRefreshDebounceSeconds, function()
            module._rosterUiHandle = nil
            if not module.IsLoggerViewingCurrentRaid() then
                return
            end
            refreshRosterBoundLists()
        end)
    end

    -- Logger helpers: resolve current raid/boss/loot and run raid actions with a single refresh.
    needRaid = function()
        local rID = module.selectedRaid
        local raid = rID and Store:GetRaid(rID) or nil
        return raid, rID
    end

    needBoss = function(raid)
        raid = raid or (select(1, needRaid()))
        if not raid then
            return nil
        end
        local bNid = module.selectedBoss
        if not bNid then
            return nil
        end
        return Store:GetBoss(raid, bNid)
    end

    needLoot = function(raid)
        raid = raid or (select(1, needRaid()))
        if not raid then
            return nil
        end
        local lNid = module.selectedItem
        if not lNid then
            return nil
        end
        return Store:GetLoot(raid, lNid)
    end

    runWithSelectedRaid = function(fn, refreshEvent)
        local raid, rID = needRaid()
        if not raid then
            return
        end
        fn(raid, rID)
        if refreshEvent ~= false then
            Bus.TriggerEvent(refreshEvent or InternalEvents.LoggerSelectRaid, module.selectedRaid)
        end
    end

    local function getExportFrameRefs()
        local frame = Frames.Get("KRTLoggerExportFrame")
        if not frame then
            return nil
        end

        return {
            frame = frame,
            hint = Frames.Ref(frame, "Hint"),
            lootBtn = Frames.Ref(frame, "LootBtn"),
            raidAttendanceBtn = Frames.Ref(frame, "RaidAttendanceBtn"),
            output = Frames.Ref(frame, "Output"),
            outputScroll = Frames.Ref(frame, "OutputScroll"),
            closeBtn = Frames.Ref(frame, "CloseBtn"),
        }
    end

    local function setExportModeButtonState(refs, mode)
        local buttons = {
            { button = refs and refs.lootBtn, mode = "loot" },
            { button = refs and refs.raidAttendanceBtn, mode = "raidAttendance" },
        }

        for i = 1, #buttons do
            local entry = buttons[i]
            local button = entry.button
            if button then
                if entry.mode == mode then
                    if button.LockHighlight then
                        button:LockHighlight()
                    end
                elseif button.UnlockHighlight then
                    button:UnlockHighlight()
                end
            end
        end
    end

    local function getExportContext()
        return {
            raidId = module.selectedRaid,
            selectedBossNid = module.selectedBoss,
            selectedPlayerNid = module.selectedBossPlayer or module.selectedPlayer,
        }
    end

    local function setExportText(refs, text)
        local output = refs and refs.output
        if not output then
            return
        end

        if output.SetTextInsets then
            output:SetTextInsets(8, 8, 8, 8)
        end
        if output.SetJustifyH then
            output:SetJustifyH("LEFT")
        end
        if output.SetJustifyV then
            output:SetJustifyV("TOP")
        end
        module._lastExportCSV = text or ""
        output:SetText(module._lastExportCSV)
        output:SetCursorPosition(0)
        output:HighlightText()
        if output.SetFocus then
            output:SetFocus()
        end

        local scroll = refs.outputScroll
        if scroll and scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        if scroll and scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(0)
        end
    end

    local function adjustExportScrollBar(refs)
        local scroll = refs and refs.outputScroll
        if not (scroll and scroll.GetName) then
            return
        end

        local scrollName = scroll:GetName()
        local scrollBar = scroll.ScrollBar or _G[scrollName .. "ScrollBar"]
        if not scrollBar then
            return
        end

        local upButton = _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downButton = _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upButton then
            upButton:ClearAllPoints()
            upButton:SetPoint("TOP", scroll, "TOPRIGHT", 10, -4)
        end
        if downButton then
            downButton:ClearAllPoints()
            downButton:SetPoint("BOTTOM", scroll, "BOTTOMRIGHT", 10, 8)
        end

        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOP", scroll, "TOPRIGHT", 10, -20)
        scrollBar:SetPoint("BOTTOM", scroll, "BOTTOMRIGHT", 10, 24)
    end

    local function refreshExportFrame(mode)
        local refs = getExportFrameRefs()
        if not refs then
            return false
        end

        local raid = needRaid()
        if not raid then
            addon:error(L.ErrLoggerInvalidRaid)
            return false
        end

        mode = mode or module._loggerExportMode or "loot"
        module._loggerExportMode = mode

        local csv, errCode = Export:GetCSV(mode, raid, getExportContext())
        if errCode then
            addon:error((L.ErrLoggerExportFailed):format(tostring(errCode)))
            return false
        end

        setExportModeButtonState(refs, mode)
        adjustExportScrollBar(refs)
        setExportText(refs, csv)
        return true
    end

    local function bindExportFrame()
        local refs = getExportFrameRefs()
        if not refs or refs.frame._krtBound then
            return refs
        end

        Frames.SetFrameTitle(refs.frame, L.StrLoggerExportTitle)
        Frames.EnableDrag(refs.frame)

        if refs.hint then
            refs.hint:SetText(L.StrLoggerExportHint)
        end
        if refs.lootBtn then
            refs.lootBtn:SetText(L.BtnLoggerExportLootCSV)
            Frames.SafeSetScript(refs.lootBtn, "OnClick", function()
                refreshExportFrame("loot")
            end)
        end
        if refs.raidAttendanceBtn then
            refs.raidAttendanceBtn:SetText(L.BtnLoggerExportRaidAttendanceCSV)
            Frames.SafeSetScript(refs.raidAttendanceBtn, "OnClick", function()
                refreshExportFrame("raidAttendance")
            end)
        end
        if refs.output and refs.output.SetTextInsets then
            refs.output:SetTextInsets(8, 8, 8, 8)
        end
        if refs.output and refs.output.SetWordWrap then
            refs.output:SetWordWrap(true)
        end
        if refs.output then
            Frames.SafeSetScript(refs.output, "OnTextChanged", function(self, userInput)
                if userInput then
                    self:SetText(module._lastExportCSV or "")
                    self:SetCursorPosition(0)
                    self:HighlightText()
                end
            end)
        end
        adjustExportScrollBar(refs)
        if refs.closeBtn then
            refs.closeBtn:SetText(L.BtnClose)
            Frames.SafeSetScript(refs.closeBtn, "OnClick", function()
                refs.frame:Hide()
            end)
        end

        refs.frame._krtBound = true
        return refs
    end

    showLoggerExportFrame = function()
        local raid = needRaid()
        if not raid then
            addon:error(L.ErrLoggerInvalidRaid)
            return false
        end

        local refs = bindExportFrame()
        if not (refs and refs.frame) then
            return false
        end

        module._loggerExportMode = "loot"
        if not refreshExportFrame(module._loggerExportMode) then
            return false
        end
        refs.frame:Show()
        return true
    end

    resetSelections = function()
        clearSelections()
    end

    function module:OnLoad(frame)
        UI.FrameName = Frames.InitModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                if not module.selectedRaid then
                    SetSelectedRaid(Core.GetCurrentRaid())
                end
                clearSelections()
                triggerSelectionEvent(module, "selectedRaid", "ui")
            end,
            hookOnHide = function()
                SetSelectedRaid(Core.GetCurrentRaid())
                clearSelections()
            end,
        }) or UI.FrameName
        UI.Loaded = UI.FrameName ~= nil
        if not UI.Loaded then
            return
        end
        Frames.SetFrameTitle(UI.FrameName, L.StrLootLogger)
    end

    local function BindHandlers(_, frame, refs)
        if refs.historyTabBtn then
            if refs.historyTabBtn.SetID then
                refs.historyTabBtn:SetID(1)
            end
            refs.historyTabBtn:SetText(L.StrHistoryTab)
            if refs.historyTabBtn.LockHighlight then
                refs.historyTabBtn:LockHighlight()
            end
        end
        if PanelTemplates_SetNumTabs then
            PanelTemplates_SetNumTabs(frame, 1)
        end
        if PanelTemplates_SetTab and refs.historyTabBtn then
            PanelTemplates_SetTab(frame, 1)
        end

        local onLoadPairs = {
            { moduleRef = module.Raids, frameRef = refs.raids },
            { moduleRef = module.Boss, frameRef = refs.bosses },
            { moduleRef = module.Loot, frameRef = refs.loot },
            { moduleRef = module.RaidAttendees, frameRef = refs.raidAttendees },
            { moduleRef = module.BossAttendees, frameRef = refs.bossAttendees },
            { moduleRef = module.BossBox, frameRef = refs.bossBox },
            { moduleRef = module.AttendeesBox, frameRef = refs.attendeesBox },
        }
        for i = 1, #onLoadPairs do
            local pair = onLoadPairs[i]
            ensureSubmoduleOnLoad(pair.moduleRef, pair.frameRef)
        end
        applyLoggerSkin()
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
        onLoad = OnLoadFrame,
    })

    function module:RefreshUI()
        local frame = getFrame()
        if not frame then
            return
        end
        if not module.selectedRaid then
            SetSelectedRaid(Core.GetCurrentRaid())
        end
        clearSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function module:Refresh()
        return self:RefreshUI()
    end

    -- Selectors
    selectRaid = function(btn, button, opts)
        if button and button ~= "LeftButton" then
            return
        end
        local raidNid = btn and btn.GetID and btn:GetID()
        if not raidNid then
            return
        end
        local raidIndex = raidNid and Core.GetRaidIdByNid(raidNid) or nil
        if not raidIndex then
            return
        end

        local modifierScope = (opts and opts.modifierScope) or module._msRaidScopeHistory or MS_SCOPE_RAID_HISTORY
        local isMulti, isRange = MultiSelect.MultiSelectResolveModifiers(modifierScope, opts)
        local prevFocus = module.selectedRaid

        local ordered = opts and opts.ordered or nil
        if not ordered then
            ordered = module.Raids and module.Raids._ctrl and module.Raids._ctrl.data or nil
        end
        local action, count = applyFocusedMultiSelect({
            id = raidNid,
            context = (opts and opts.context) or MS_CTX_RAID,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            allowDeselect = opts and opts.allowDeselect,
            setFocus = SetSelectedRaid,
            mapSelectedToFocus = function(nid)
                return nid and Core.GetRaidIdByNid(nid) or nil
            end,
            isClickedFocused = function(clickedNid)
                local selectedRaidNid = module.selectedRaid and Core.GetRaidNidById(module.selectedRaid) or nil
                return selectedRaidNid == clickedNid
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickRaid):format(
                    tostring(raidNid),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedRaid)
                )
            )
        end

        -- If the focused raid changed, reset dependent selections (boss/player/loot panels).
        if prevFocus ~= module.selectedRaid then
            clearSelections()
        end

        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    selectBoss = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.MultiSelectResolveModifiers(MS_SCOPE_BOSS)
        local prevFocus = module.selectedBoss

        local ordered = module.Boss and module.Boss._ctrl and module.Boss._ctrl.data or nil
        local action, count = applyFocusedMultiSelect({
            id = id,
            context = MS_CTX_BOSS,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            getFocus = function()
                return module.selectedBoss
            end,
            setFocus = function(v)
                module.selectedBoss = v
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickBoss):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedBoss)
                )
            )
        end

        -- If the focused boss changed, reset boss-attendees + loot selection (filters changed).
        if prevFocus ~= module.selectedBoss then
            clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
            triggerSelectionEvent(module, "selectedBossPlayer")
        end

        triggerSelectionEvent(module, "selectedBoss")
    end

    -- Player filter: only one active at a time
    selectBossPlayer = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.MultiSelectResolveModifiers(MS_SCOPE_BOSSATT)
        local prevFocus = module.selectedBossPlayer

        -- Mutual exclusion: selecting a boss-attendee filter clears the raid-attendee filter (and its multi-select).
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)

        local ordered = module.BossAttendees and module.BossAttendees._ctrl and module.BossAttendees._ctrl.data or nil
        local action, count = applyFocusedMultiSelect({
            id = id,
            context = MS_CTX_BOSSATT,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            getFocus = function()
                return module.selectedBossPlayer
            end,
            setFocus = function(v)
                module.selectedBossPlayer = v
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickBossAttendees):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedBossPlayer)
                )
            )
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedBossPlayer then
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
        end

        triggerSelectionEvent(module, "selectedBossPlayer")
        triggerSelectionEvent(module, "selectedPlayer")
    end

    selectPlayer = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.MultiSelectResolveModifiers(MS_SCOPE_RAIDATT)
        local prevFocus = module.selectedPlayer

        -- Mutual exclusion: selecting a raid-attendee filter clears the boss-attendee filter (and its multi-select).
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)

        local ordered = module.RaidAttendees and module.RaidAttendees._ctrl and module.RaidAttendees._ctrl.data or nil
        local action, count = applyFocusedMultiSelect({
            id = id,
            context = MS_CTX_RAIDATT,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            getFocus = function()
                return module.selectedPlayer
            end,
            setFocus = function(v)
                module.selectedPlayer = v
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickRaidAttendees):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedPlayer)
                )
            )
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedPlayer then
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
        end

        triggerSelectionEvent(module, "selectedPlayer")
        triggerSelectionEvent(module, "selectedBossPlayer")
    end

    -- Item: left select, right menu
    do
        local quickRollTypes = {
            { rollType = rollTypes.MAINSPEC, label = L.BtnMS, suffix = "MS" },
            { rollType = rollTypes.OFFSPEC, label = L.BtnOS, suffix = "OS" },
            { rollType = rollTypes.RESERVED, label = L.BtnSR, suffix = "SR" },
            { rollType = rollTypes.FREE, label = L.BtnFree, suffix = "Free" },
            { rollType = rollTypes.BANK, label = L.BtnBank, suffix = "Bank" },
            { rollType = rollTypes.DISENCHANT, label = L.BtnDisenchant, suffix = "DE" },
            { rollType = rollTypes.HOLD, label = L.BtnHold, suffix = "Hold" },
        }
        local ROLLTYPE_POPUP_KEY = "KRTLOGGER_ITEM_EDIT_ROLL_PICK"
        local ROLLTYPE_PICKER_FRAME = "KRTLoggerRollTypePickerFrame"
        local ROLLTYPE_BUTTON_MIN_WIDTH = 42
        local ROLLTYPE_BUTTON_MAX_WIDTH = 54
        local ROLLTYPE_BUTTON_HEIGHT = 22
        local ROLLTYPE_BUTTON_SPACING = 3
        local ROLLTYPE_PICKER_SIDE_PADDING = 24
        local ROLLTYPE_PICKER_TOP_OFFSET = 8
        local ROLLTYPE_POPUP_EXTRA_HEIGHT = 16

        local function applySelectedLootRollType(lootNid, rollType)
            if not lootNid then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end
            module.Loot:SetLootEntry(lootNid, nil, rollType, nil, "LOGGER_EDIT_ROLLTYPE")
        end

        local function getItemMenuFrame()
            return _G.KRTLoggerItemMenuFrame or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
        end

        local function ensureRollTypeInsertedFrame()
            local frame = _G[ROLLTYPE_PICKER_FRAME]
            if not frame then
                return nil
            end

            if frame._buttons and frame._initialized then
                return frame
            end

            frame._buttons = frame._buttons or {}
            local frameName = frame.GetName and frame:GetName() or ROLLTYPE_PICKER_FRAME
            local count = #quickRollTypes
            for i = 1, count do
                local entry = quickRollTypes[i]
                local rollType = entry.rollType
                local button = _G[frameName .. entry.suffix]
                if button then
                    button:SetText(entry.label)
                    button:SetScript("OnClick", function(btn)
                        local parent = btn and btn.GetParent and btn:GetParent() or nil
                        applySelectedLootRollType(parent and parent.lootNid, rollType)
                        StaticPopup_Hide(ROLLTYPE_POPUP_KEY)
                    end)
                end
                frame._buttons[i] = button
            end
            frame._initialized = true
            return frame
        end

        local function layoutRollTypeInsertedFrame(popup, picker)
            local count = #quickRollTypes
            local spacing = ROLLTYPE_BUTTON_SPACING
            local sidePadding = ROLLTYPE_PICKER_SIDE_PADDING
            local popupWidth = popup:GetWidth()

            local available = popupWidth - (sidePadding * 2) - (spacing * (count - 1))
            local buttonWidth = math.floor(available / count)
            if buttonWidth < ROLLTYPE_BUTTON_MIN_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MIN_WIDTH
                local minPopupWidth = (buttonWidth * count) + (spacing * (count - 1)) + (sidePadding * 2)
                if popupWidth < minPopupWidth then
                    popup:SetWidth(minPopupWidth)
                    popupWidth = popup:GetWidth()
                    available = popupWidth - (sidePadding * 2) - (spacing * (count - 1))
                    buttonWidth = math.floor(available / count)
                end
            end
            if buttonWidth > ROLLTYPE_BUTTON_MAX_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MAX_WIDTH
            end
            if buttonWidth < ROLLTYPE_BUTTON_MIN_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MIN_WIDTH
            end

            local rowWidth = (buttonWidth * count) + (spacing * (count - 1))
            picker:SetWidth(rowWidth)
            picker:SetHeight(ROLLTYPE_BUTTON_HEIGHT)

            local prevButton
            for i = 1, count do
                local button = picker._buttons and picker._buttons[i]
                if button then
                    button:ClearAllPoints()
                    button:SetWidth(buttonWidth)
                    button:SetHeight(ROLLTYPE_BUTTON_HEIGHT)
                    if i == 1 then
                        button:SetPoint("LEFT", picker, "LEFT", 0, 0)
                    else
                        button:SetPoint("LEFT", prevButton, "RIGHT", spacing, 0)
                    end
                    prevButton = button
                end
            end
        end

        local function ensureRollTypePopup()
            if not StaticPopupDialogs then
                return false
            end
            if StaticPopupDialogs[ROLLTYPE_POPUP_KEY] then
                return true
            end

            ensureRollTypeInsertedFrame()

            StaticPopupDialogs[ROLLTYPE_POPUP_KEY] = {
                text = L.StrEditItemRollType,
                button1 = L.BtnCancel,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                wide = 1,
                preferredIndex = 3,
                OnShow = function(self, data)
                    local itemId = data and data.itemId or module.selectedItem
                    local picker = ensureRollTypeInsertedFrame()
                    if not picker then
                        return
                    end
                    self._krtExtraHeight = picker:GetHeight() + ROLLTYPE_POPUP_EXTRA_HEIGHT

                    if not self._krtSavedSetHeight then
                        self._krtSavedSetHeight = self.SetHeight
                        self.SetHeight = function(dialog, h)
                            local base = dialog._krtSavedSetHeight
                            if not base then
                                return
                            end
                            local extra = dialog._krtExtraHeight or 0
                            return base(dialog, h + extra)
                        end
                    end

                    if self.text then
                        self.text:SetWidth(self:GetWidth() - 36)
                    end
                    if StaticPopup_Resize then
                        StaticPopup_Resize(self, self.which)
                    end
                    layoutRollTypeInsertedFrame(self, picker)

                    picker.lootNid = itemId
                    picker:SetParent(self)
                    picker:ClearAllPoints()
                    if self.text then
                        picker:SetPoint("TOP", self.text, "BOTTOM", 0, -ROLLTYPE_PICKER_TOP_OFFSET)
                    else
                        picker:SetPoint("TOP", self, "TOP", 0, -44)
                    end
                    picker:SetFrameLevel((self:GetFrameLevel() or 1) + 1)
                    picker:Show()
                end,
                OnHide = function(self)
                    if self._krtSavedSetHeight then
                        self.SetHeight = self._krtSavedSetHeight
                        self._krtSavedSetHeight = nil
                    end
                    self._krtExtraHeight = nil
                    local picker = _G[ROLLTYPE_PICKER_FRAME]
                    if picker then
                        picker.lootNid = nil
                        picker:Hide()
                        picker:SetParent(UIParent)
                    end
                end,
            }
            return true
        end

        local function openItemRollTypePopup()
            local lootNid = module.selectedItem
            if not lootNid then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end

            if not ensureRollTypePopup() then
                return
            end

            CloseDropDownMenus()
            StaticPopup_Show(ROLLTYPE_POPUP_KEY, nil, nil, {
                itemId = lootNid,
            })
        end

        local function openItemMenu()
            local f = getItemMenuFrame()

            EasyMenu({
                {
                    text = L.StrEditItemLooter,
                    notCheckable = 1,
                    func = function()
                        StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER")
                    end,
                },
                {
                    text = L.StrEditItemRollType,
                    notCheckable = 1,
                    func = openItemRollTypePopup,
                },
                {
                    text = L.StrEditItemRollValue,
                    notCheckable = 1,
                    func = function()
                        StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE")
                    end,
                },
            }, f, "cursor", 0, 0, "MENU")
        end

        selectItem = function(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then
                return
            end

            -- NOTE: Multi-select is maintained in MultiSelect module (context = MS_CTX_LOOT).
            if button == "LeftButton" then
                local isMulti, isRange = MultiSelect.MultiSelectResolveModifiers(MS_SCOPE_LOOT)

                local ordered = module.Loot and module.Loot._ctrl and module.Loot._ctrl.data or nil
                local action, count = applyFocusedMultiSelect({
                    id = id,
                    context = MS_CTX_LOOT,
                    ordered = ordered,
                    isMulti = isMulti,
                    isRange = isRange,
                    getFocus = function()
                        return module.selectedItem
                    end,
                    setFocus = function(v)
                        module.selectedItem = v
                    end,
                })

                if Options.IsDebugEnabled() and addon.debug then
                    addon:debug(
                        (Diag.D.LogLoggerSelectClickLoot):format(
                            tostring(id),
                            isMulti and 1 or 0,
                            isRange and 1 or 0,
                            tostring(action),
                            tonumber(count) or 0,
                            tostring(module.selectedItem)
                        )
                    )
                end

                triggerSelectionEvent(module, "selectedItem")
            elseif button == "RightButton" then
                -- Context menu works on a single focused row.
                local action, count = MultiSelect.MultiSelectToggle(MS_CTX_LOOT, id, false)
                module.selectedItem = id

                if Options.IsDebugEnabled() and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickContextMenu):format(tostring(id), tostring(action), tonumber(count) or 0))
                end

                triggerSelectionEvent(module, "selectedItem")
                openItemMenu()
            end
        end

        -- Keep row hover neutral; item tooltip is bound to icon hover only.
        onLootRowEnter = function(_row)
            -- No-op.
        end

        onLootRowLeave = function(_row)
            -- No-op.
        end

        local function validateRollValue(_, text)
            local ok, value = Helpers.IsValidRollValue(text)
            if not ok then
                addon:error(L.ErrLoggerInvalidRollValue)
                return false
            end
            return true, value
        end

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp, function(self, text)
            local rawText = Strings.TrimText(text)
            local name = Strings.NormalizeLower(rawText)
            if not name or name == "" then
                addon:error(L.ErrLoggerWinnerEmpty)
                return
            end
            local raid = Store:GetRaid(self.raidId)
            if not raid then
                addon:error(L.ErrLoggerInvalidRaid)
                return
            end

            local loot = Store:GetLoot(raid, self.lootNid)
            if not loot then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end

            local bossKill = (loot.bossNid and raid) and Store:GetBoss(raid, loot.bossNid) or nil
            local winner = Helpers.FindLoggerPlayer(name, raid, bossKill)
            if not winner then
                addon:error(L.ErrLoggerWinnerNotFound:format(rawText))
                return
            end

            module.Loot:SetLootEntry(self.lootNid, winner, nil, nil, "LOGGER_EDIT_WINNER")
        end, function(self)
            self.raidId = module.selectedRaid
            self.lootNid = module.selectedItem
        end)

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp, function(self, text)
            module.Loot:SetLootEntry(self.lootNid, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
        end, function(self)
            self.lootNid = module.selectedItem
        end, validateRollValue)
    end
end

-- Shared factory for Logger list controllers with standardized highlight/focus config.
local function makeLoggerList(cfg, selField, msCtxField, hlOpts)
    hlOpts = hlOpts or {}
    local transform = hlOpts.transform
    local debugTag = hlOpts.debugTag or "LoggerSelect"

    -- Logger XML already reserves a right scrollbar column via ScrollFrame anchors.
    -- Keep ListController from subtracting a second right inset in Logger tables.
    if cfg.rightInset == nil then
        cfg.rightInset = 0
    end
    if cfg.drawRow then
        local drawRow = cfg.drawRow
        cfg.drawRow = function(row, it)
            styleLoggerRow(row)
            return drawRow(row, it)
        end
    end

    local function resolve()
        local v = module[selField]
        if v == nil then
            return nil
        end
        return transform and transform(v) or v
    end

    if msCtxField then
        cfg.highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module[msCtxField], id)
        end
        cfg.highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module[msCtxField])
        end
        cfg.highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module[msCtxField]), MultiSelect.MultiSelectCount(module[msCtxField]))
        end
    else
        cfg.highlightId = resolve
        cfg.highlightDebugInfo = function()
            return ("%s=%s"):format(selField, tostring(resolve()))
        end
    end

    cfg.focusId = resolve
    cfg.focusKey = function()
        return tostring(resolve() or "nil")
    end
    cfg.highlightDebugTag = debugTag
    return ListController.MakeListController(cfg)
end

-- Raids list.
do
    module.Raids = module.Raids or {}
    local Raids = module.Raids
    local Store = module.Store
    local Helpers = module.Helpers
    local controller
    controller = makeLoggerList(
        {
            keyName = "RaidsList",
            poolTag = "logger-raids",
            _rowParts = { "ID", "Date", "Zone", "Size" },

            localize = function(n)
                local title = _G[n .. "Title"]
                if title then
                    title:SetText(L.StrRaidsList)
                end
                _G[n .. "HeaderNum"]:SetText(L.StrNumber)
                _G[n .. "HeaderDate"]:SetText(L.StrDate)
                _G[n .. "HeaderZone"]:SetText(L.StrZone)
                _G[n .. "HeaderSize"]:SetText(L.StrSize)
                _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
                local del = _G[n .. "DeleteBtn"]
                if del then
                    del:SetText(L.BtnDelete)
                end
                Frames.SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)

                local frame = _G[n]
                if frame and not frame._krtBound then
                    Frames.SafeSetScript(_G[n .. "CurrentBtn"], "OnClick", function(self, button)
                        Raids:SetCurrent(self, button)
                    end)
                    Frames.SafeSetScript(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                        Raids:Delete(self, button)
                    end)
                    bindRaidSortHeaders(n, Raids)
                end
            end,

            getData = function(out)
                fillRaidListData(out, "Logger.Raids.GetData")
            end,

            rowName = function(n, _, i)
                return n .. "RaidBtn" .. i
            end,
            rowTmpl = "KRTLoggerRaidButton",

            drawRow = ListController.CreateRowDrawer(function(row, it)
                if not row._krtBound then
                    Frames.SafeSetScript(row, "OnClick", function(self, button)
                        selectRaid(self, button)
                    end)
                    row._krtBound = true
                end
                local ui = row._p
                ui.ID:SetText(it.seq or it.id)
                ui.Date:SetText(it.dateFmt)
                ui.Zone:SetText(it.zone)
                ui.Size:SetText(it.sizeLabel or it.size)
            end),

            postUpdate = function(n)
                local sel = module.selectedRaid
                local raid = sel and Core.EnsureRaidById(sel) or nil
                local count = controller and controller.data and #controller.data or 0

                local canSetCurrent = false
                if sel and raid and sel ~= Core.GetCurrentRaid() then
                    -- This button is intended to resolve duplicate raid creation while actively raiding.
                    if not addon.IsInRaid() then
                        canSetCurrent = false
                    elseif Services.Raid:Expired(sel) then
                        canSetCurrent = false
                    else
                        local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
                        if isDyn then
                            instanceDiff = instanceDiff + (2 * dynDiff)
                        end
                        if instanceType == "raid" then
                            local raidSize = tonumber(raid.size)
                            local groupSize = Services.Raid:GetRaidSize()
                            local zoneOk = (not raid.zone) or (raid.zone == instanceName)
                            local raidDiff = tonumber(raid.difficulty)
                            local curDiff = tonumber(instanceDiff)
                            local diffOk = raidDiff and curDiff and (raidDiff == curDiff)
                            canSetCurrent = zoneOk and raidSize and (raidSize == groupSize) and diffOk
                        end
                    end
                end

                UIPrimitives.EnableDisable(_G[n .. "CurrentBtn"], canSetCurrent)

                local ctx = module._msRaidCtx
                local selCount = MultiSelect.MultiSelectCount(ctx)
                local canDelete = (selCount and selCount > 0) or false
                if canDelete and Core.GetCurrentRaid() then
                    local currentRaidNid = Core.GetRaidNidById(Core.GetCurrentRaid())
                    local ids = MultiSelect.MultiSelectGetSelected(ctx)
                    for i = 1, #ids do
                        if currentRaidNid and tonumber(ids[i]) == tonumber(currentRaidNid) then
                            canDelete = false
                            break
                        end
                    end
                end
                local delBtn = _G[n .. "DeleteBtn"]
                UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, selCount)
                UIPrimitives.EnableDisable(delBtn, canDelete)
                setPanelTitle(n, Helpers.GetCountTitle(L.StrRaidsList, count))
                setFrameHint(n, "EmptyState", count == 0 and L.StrLoggerEmptyRaids or nil)
            end,

            sorters = {
                id = function(a, b, asc)
                    return CompareNumbers(a.seq or a.id, b.seq or b.id, asc, 0)
                end,
                date = function(a, b, asc)
                    return CompareNumbers(a.date, b.date, asc, 0)
                end,
                zone = function(a, b, asc)
                    return CompareStrings(a.zone, b.zone, asc)
                end,
                size = function(a, b, asc)
                    return CompareNumbers(a.size, b.size, asc, 0)
                end,
            },
        },
        "selectedRaid",
        "_msRaidCtx",
        {
            transform = function(id)
                return Core.GetRaidNidById(id)
            end,
        }
    )

    Raids._ctrl = controller
    ListController.BindListController(Raids, controller)

    function Raids:SetCurrent(btn)
        if not btn then
            return
        end
        local sel = module.selectedRaid
        if not sel then
            return
        end
        if module.Actions:SetCurrentRaid(sel) then
            -- Context change: clear dependent selections and redraw all module panels.
            SetSelectedRaid(sel)
            resetSelections()
            triggerSelectionEvent(module, "selectedRaid", "ui")
        end
    end

    do
        local function deleteRaids()
            local ctx = module._msRaidCtx
            local ids = MultiSelect.MultiSelectGetSelected(ctx)
            if not (ids and #ids > 0) then
                return
            end

            local raidNids = {}
            local seenNids = {}
            for i = 1, #ids do
                local nid = tonumber(ids[i])
                if nid and not seenNids[nid] then
                    seenNids[nid] = true
                    raidNids[#raidNids + 1] = nid
                end
            end
            if #raidNids == 0 then
                return
            end

            -- Safety: never delete the current raid
            local currentRaidNid = Core.GetRaidNidById(Core.GetCurrentRaid())
            if currentRaidNid then
                for i = 1, #raidNids do
                    if tonumber(raidNids[i]) == tonumber(currentRaidNid) then
                        return
                    end
                end
            end

            local prevFocus = module.selectedRaid
            local prevFocusNid = prevFocus and Core.GetRaidNidById(prevFocus) or nil
            for i = 1, #raidNids do
                module.Actions:DeleteRaidByNid(raidNids[i])
            end

            MultiSelect.MultiSelectClear(ctx)

            local raidStore = Core.GetRaidStoreOrNil("Logger.Raids.DeleteRaids", { "GetAllRaids" })
            local raids = raidStore and raidStore:GetAllRaids() or {}
            local n = #raids
            local newFocus = nil
            if n > 0 then
                newFocus = prevFocusNid and Core.GetRaidIdByNid(prevFocusNid) or nil
                if not newFocus then
                    local base = tonumber(prevFocus) or n
                    if base > n then
                        base = n
                    end
                    if base < 1 then
                        base = 1
                    end
                    newFocus = base
                end
            end

            SetSelectedRaid(newFocus)
            resetSelections()
            controller:Dirty()
            triggerSelectionEvent(module, "selectedRaid", "ui")
        end

        function Raids:Delete(btn)
            local ctx = module._msRaidCtx
            if btn and MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, deleteRaids)
    end

    Bus.RegisterCallback(InternalEvents.RaidCreate, function(_, num)
        -- Context change: selecting a different raid must clear dependent selections.
        SetSelectedRaid(tonumber(num))
        resetSelections()
        controller:Dirty()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end)

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function(_, raidId, reason)
        local raidIdType = type(raidId)
        if raidId ~= nil and raidIdType ~= "number" and raidIdType ~= "string" then
            addon:warn(Diag.W.LogLoggerSelectRaidPayloadInvalid:format(tostring(raidId), tostring(reason)))
            return
        end
        if reason ~= nil and reason ~= "ui" and reason ~= "sync" then
            addon:warn(Diag.W.LogLoggerSelectRaidPayloadInvalid:format(tostring(raidId), tostring(reason)))
            return
        end

        local prevRaid = module.selectedRaid
        SetSelectedRaid(raidId)

        if prevRaid ~= module.selectedRaid then
            resetSelections()
        end

        if reason == "sync" then
            local raid = module.selectedRaid and Store:GetRaid(module.selectedRaid) or nil
            if raid and Store._InvalidateIndexes then
                Store._InvalidateIndexes(raid)
            end
        end

        if reason == "sync" then
            -- Sync can change raid rows; force data refetch instead of highlight-only refresh.
            controller:Dirty()
        else
            controller:Touch()
        end
    end)

    Bus.RegisterCallback(InternalEvents.RaidRosterDelta, function(_, delta, rosterVersion, raidId)
        local raidIdType = type(raidId)
        if type(delta) ~= "table" then
            return
        end
        if type(rosterVersion) ~= "number" then
            return
        end
        if raidId == nil then
            return
        end
        if raidIdType ~= "number" and raidIdType ~= "string" then
            return
        end
        if not module.IsLoggerViewingCurrentRaid() then
            return
        end

        module.RequestRosterBoundListsRefresh()
    end)
end

-- Boss list.
do
    module.Boss = module.Boss or {}
    local Boss = module.Boss
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions
    local Helpers = module.Helpers
    local editSelectedBoss

    local controller
    controller = makeLoggerList({
        keyName = "BossList",
        poolTag = "logger-bosses",
        _rowParts = { "ID", "Name", "Time", "Mode" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrBosses)
            end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
            _G[n .. "HeaderMode"]:SetText(L.StrMode)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            local del = _G[n .. "DeleteBtn"]
            if del then
                del:SetText(L.BtnDelete)
            end
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "AddBtn"], "OnClick", function()
                    Boss:Add()
                end)
                Frames.SafeSetScript(_G[n .. "EditBtn"], "OnClick", function()
                    editSelectedBoss()
                end)
                Frames.SafeSetScript(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                    Boss:Delete(self, button)
                end)
                Frames.SafeSetScript(_G[n .. "HeaderNum"], "OnClick", function()
                    Boss:Sort("id")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderName"], "OnClick", function()
                    Boss:Sort("name")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderTime"], "OnClick", function()
                    Boss:Sort("time")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderMode"], "OnClick", function()
                    Boss:Sort("mode")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end
            View:FillBossList(out, raid)
        end,

        rowName = function(n, _, i)
            return n .. "BossBtn" .. i
        end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    selectBoss(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            -- Display a sequential number that rescales after deletions.
            -- Keep it.id as the stable bossNid for selection/highlight.
            ui.ID:SetText(it.seq)
            ui.Name:SetText(it.name)
            ui.Time:SetText(it.timeFmt)
            ui.Mode:SetText(it.mode)
        end),

        postUpdate = function(n)
            local hasRaid = module.selectedRaid
            local hasBoss = module.selectedBoss
            local count = controller and controller.data and #controller.data or 0
            UIPrimitives.EnableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            UIPrimitives.EnableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            local bossSelCount = MultiSelect.MultiSelectCount(module._msBossCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, bossSelCount)
            UIPrimitives.EnableDisable(delBtn, (bossSelCount and bossSelCount > 0) or false)
            setPanelTitle(n, Helpers.GetCountContextTitle(L.StrBosses, count, Helpers.GetRaidContextLabel(module.selectedRaid), nil))
            setFrameHint(n, "EmptyState", Helpers.GetBossEmptyStateText(count, module.selectedRaid))
        end,

        sorters = {
            -- Sort by the displayed sequential number, not the stable nid.
            id = function(a, b, asc)
                return CompareNumbers(a.seq, b.seq, asc, 0)
            end,
            name = function(a, b, asc)
                return CompareStrings(a.name, b.name, asc)
            end,
            time = function(a, b, asc)
                return CompareNumbers(a.time, b.time, asc, 0)
            end,
            mode = function(a, b, asc)
                return CompareStrings(a.mode, b.mode, asc)
            end,
        },
    }, "selectedBoss", "_msBossCtx")

    Boss._ctrl = controller
    ListController.BindListController(Boss, controller)

    function Boss:Add()
        module.BossBox:Toggle()
    end

    editSelectedBoss = function()
        if module.selectedBoss then
            fillBossBox()
        end
    end

    do
        local function deleteBosses()
            runWithSelectedRaid(function(_, rID)
                local ctx = module._msBossCtx
                local ids = MultiSelect.MultiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then
                    return
                end

                for i = 1, #ids do
                    local bNid = ids[i]
                    local lootRemoved = Actions:DeleteBoss(rID, bNid)
                    if addon.hasDebug then
                        addon:debug(Diag.D.LogLoggerBossLootRemoved, rID, tonumber(bNid) or -1, lootRemoved)
                    end
                end

                -- Clear boss-related selections (filters changed / deleted)
                MultiSelect.MultiSelectClear(ctx)
                module.selectedBoss = nil

                module.selectedBossPlayer = nil
                MultiSelect.MultiSelectClear(module._msBossAttCtx)

                module.selectedItem = nil
                MultiSelect.MultiSelectClear(module._msLootCtx)
            end)
        end

        function Boss:Delete()
            local ctx = module._msBossCtx
            if MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, deleteBosses)
    end

    function Boss:GetName(bossNid, raidId)
        local rID = raidId or module.selectedRaid
        if not rID then
            return ""
        end
        bossNid = bossNid or module.selectedBoss
        if not bossNid then
            return ""
        end

        local raid = Store:GetRaid(rID)
        if not raid then
            return ""
        end
        local boss = raid and Store:GetBoss(raid, bossNid) or nil
        return boss and boss.name or ""
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function()
        controller:Dirty()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectBoss, function()
        controller:Touch()
    end)
end

-- Boss attendees list.
do
    module.BossAttendees = module.BossAttendees or {}
    local BossAtt = module.BossAttendees
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions
    local Helpers = module.Helpers

    local controller
    controller = makeLoggerList({
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrBossAttendees)
            end
            local add = _G[n .. "AddBtn"]
            if add then
                add:SetText(L.BtnAdd)
            end
            local rm = _G[n .. "RemoveBtn"]
            if rm then
                rm:SetText(L.BtnRemove)
            end
            _G[n .. "HeaderName"]:SetText(L.StrName)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "AddBtn"], "OnClick", function()
                    BossAtt:Add()
                end)
                Frames.SafeSetScript(_G[n .. "RemoveBtn"], "OnClick", function(self, button)
                    BossAtt:Delete(self, button)
                end)
                Frames.SafeSetScript(_G[n .. "HeaderName"], "OnClick", function()
                    BossAtt:Sort("name")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local rID = module.selectedRaid
            local bID = module.selectedBoss
            local raid = (rID and bID) and Store:GetRaid(rID) or nil
            if not (raid and bID) then
                return
            end
            View:FillBossAttendeesList(out, raid, bID)
        end,

        rowName = function(n, _, i)
            return n .. "PlayerBtn" .. i
        end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    selectBossPlayer(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            local r, g, b = Colors.GetClassColor(it.class)
            ui.Name:SetText(it.name)
            ui.Name:SetVertexColor(r, g, b)
        end),

        postUpdate = function(n)
            local bSel = module.selectedBoss
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = MultiSelect.MultiSelectCount(module._msBossAttCtx)
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, Helpers.GetCountContextTitle(L.StrBossAttendees, count, Helpers.GetBossContextLabel(module.selectedRaid, module.selectedBoss), nil))
            setFrameHint(n, "EmptyState", Helpers.GetBossAttendeesEmptyStateText(count, module.selectedRaid, module.selectedBoss))
            if addBtn then
                UIPrimitives.EnableDisable(addBtn, bSel and ((attSelCount or 0) == 0))
            end
            if removeBtn then
                UIPrimitives.SetButtonCount(removeBtn, L.BtnRemove, attSelCount)
                UIPrimitives.EnableDisable(removeBtn, bSel and ((attSelCount or 0) > 0))
            end
        end,

        sorters = {
            name = function(a, b, asc)
                return CompareStrings(a.name, b.name, asc)
            end,
        },
    }, "selectedBossPlayer", "_msBossAttCtx")

    BossAtt._ctrl = controller
    ListController.BindListController(BossAtt, controller)

    function BossAtt:Add()
        module.AttendeesBox:Toggle()
    end

    do
        local function deleteAttendees()
            deleteSelectedAttendees(module._msBossAttCtx, function(rID, ids)
                local bNid = module.selectedBoss
                if not bNid then
                    return 0
                end

                for i = 1, #ids do
                    Actions:DeleteBossAttendee(rID, bNid, ids[i])
                end
                return #ids
            end, function()
                module.selectedBossPlayer = nil
            end)
        end

        function BossAtt:Delete()
            local ctx = module._msBossAttCtx
            if MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, deleteAttendees)
    end

    Bus.RegisterCallbacks({
        InternalEvents.LoggerSelectRaid,
        InternalEvents.LoggerSelectBoss,
    }, function()
        controller:Dirty()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectBossPlayer, function()
        controller:Touch()
    end)
end

-- Raid attendees list.
do
    module.RaidAttendees = module.RaidAttendees or {}
    local RaidAtt = module.RaidAttendees
    local View = module.View
    local Actions = module.Actions
    local Helpers = module.Helpers

    local controller
    controller = makeLoggerList({
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrRaidAttendees)
            end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                addBtn:SetText(L.BtnUpdate)
                local del = _G[n .. "DeleteBtn"]
                if del then
                    del:SetText(L.BtnDelete)
                end
                addBtn:Disable() -- enabled in postUpdate when applicable
            end

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "AddBtn"], "OnClick", function()
                    RaidAtt:Add()
                end)
                Frames.SafeSetScript(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                    RaidAtt:Delete(self, button)
                end)
                Frames.SafeSetScript(_G[n .. "HeaderName"], "OnClick", function()
                    RaidAtt:Sort("name")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderJoin"], "OnClick", function()
                    RaidAtt:Sort("join")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderLeave"], "OnClick", function()
                    RaidAtt:Sort("leave")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end
            View:FillRaidAttendeesList(out, raid)
        end,

        rowName = function(n, _, i)
            return n .. "PlayerBtn" .. i
        end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    selectPlayer(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            ui.Name:SetText(it.name)
            local r, g, b = Colors.GetClassColor(it.class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Join:SetText(it.joinFmt)
            ui.Leave:SetText(it.leaveFmt)
        end),

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, Helpers.GetCountContextTitle(L.StrRaidAttendees, count, Helpers.GetRaidContextLabel(module.selectedRaid), nil))
            setFrameHint(n, "EmptyState", Helpers.GetRaidAttendeesEmptyStateText(count, module.selectedRaid))
            if deleteBtn then
                local attSelCount = MultiSelect.MultiSelectCount(module._msRaidAttCtx)
                UIPrimitives.SetButtonCount(deleteBtn, L.BtnDelete, attSelCount)
                UIPrimitives.EnableDisable(deleteBtn, (attSelCount and attSelCount > 0) or false)
            end

            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                -- Update is only meaningful for the current raid session while actively raiding.
                local can = addon.IsInRaid() and Core.GetCurrentRaid() and module.selectedRaid and (tonumber(Core.GetCurrentRaid()) == tonumber(module.selectedRaid))
                UIPrimitives.EnableDisable(addBtn, can)
            end
        end,

        sorters = {
            name = function(a, b, asc)
                return CompareStrings(a.name, b.name, asc)
            end,
            join = function(a, b, asc)
                return CompareNumbers(a.join, b.join, asc, 0)
            end,
            leave = function(a, b, asc)
                local missing = asc and math.huge or -math.huge
                return CompareNumbers(a.leave, b.leave, asc, missing)
            end,
        },
    }, "selectedPlayer", "_msRaidAttCtx")

    RaidAtt._ctrl = controller
    ListController.BindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function RaidAtt:Add()
        runWithSelectedRaid(function(_, rID)
            local sel = tonumber(rID)
            if not sel then
                return
            end

            if not addon.IsInRaid() then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotInRaid)
                return
            end

            if not (Core.GetCurrentRaid() and tonumber(Core.GetCurrentRaid()) == sel) then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotCurrent)
                return
            end

            -- Update the roster from the live in-game raid roster.
            Services.Raid:UpdateRaidRoster()

            -- Clear dependent selections after roster sync.
            MultiSelect.MultiSelectClear(module._msRaidAttCtx)
            MultiSelect.MultiSelectClear(module._msBossAttCtx)
            MultiSelect.MultiSelectClear(module._msLootCtx)
            module.selectedPlayer = nil
            module.selectedBossPlayer = nil
            module.selectedItem = nil

            controller:Dirty()
        end)
    end

    do
        local function deleteAttendees()
            deleteSelectedAttendees(module._msRaidAttCtx, function(rID, ids)
                local removed = Actions:DeleteRaidAttendeeMany(rID, ids)
                return tonumber(removed) or 0
            end, function()
                module.selectedPlayer = nil

                -- Player filters changed: clear boss-attendees selection too.
                module.selectedBossPlayer = nil
                MultiSelect.MultiSelectClear(module._msBossAttCtx)

                -- Filters changed: reset loot selection.
                module.selectedItem = nil
                MultiSelect.MultiSelectClear(module._msLootCtx)
            end)
        end

        function RaidAtt:Delete()
            local ctx = module._msRaidAttCtx
            if MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, deleteAttendees)
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function()
        controller:Dirty()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectPlayer, function()
        controller:Touch()
    end)
end

-- Loot list (filters by selected boss and player).
do
    module.Loot = module.Loot or {}
    local Loot = module.Loot
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions
    local Helpers = module.Helpers
    local sortLoot
    local showLootTooltip

    local function updateSourceHeaderState(frameName)
        local header = frameName and _G[frameName .. "HeaderSource"]
        if not header then
            return
        end

        local canSortSource = module.selectedBoss == nil
        if header.EnableMouse then
            header:EnableMouse(canSortSource)
        end
        if header.SetAlpha then
            header:SetAlpha(canSortSource and 1 or 0.6)
        end
    end

    local controller
    controller = makeLoggerList({
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture", "ItemNormalTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrRaidLoot)
            end
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            _G[n .. "ClearBtn"]:SetText(L.BtnClear)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "HeaderItem"]:SetText(L.StrItem)
            _G[n .. "HeaderSource"]:SetText(L.StrSource)
            _G[n .. "HeaderWinner"]:SetText(L.StrWinner)
            _G[n .. "HeaderType"]:SetText(L.StrType)
            _G[n .. "HeaderRoll"]:SetText(L.StrRoll)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)

            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            local del = _G[n .. "DeleteBtn"]
            if del then
                del:SetText(L.BtnDelete)
            end
            _G[n .. "EditBtn"]:Disable()
            UIPrimitives.EnableDisable(_G[n .. "ExportBtn"], module.selectedRaid ~= nil)
            updateSourceHeaderState(n)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "ExportBtn"], "OnClick", function()
                    showLoggerExportFrame()
                end)
                Frames.SafeSetScript(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                    Loot:Delete(self, button)
                end)
                Frames.SafeSetScript(_G[n .. "HeaderItem"], "OnClick", function()
                    sortLoot("id")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderSource"], "OnClick", function()
                    sortLoot("source")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderWinner"], "OnClick", function()
                    sortLoot("winner")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderType"], "OnClick", function()
                    sortLoot("type")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderRoll"], "OnClick", function()
                    sortLoot("roll")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderTime"], "OnClick", function()
                    sortLoot("time")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end

            local bID = module.selectedBoss
            local pID = module.selectedBossPlayer or module.selectedPlayer
            local p = pID and Store:GetPlayer(raid, pID) or nil
            local pName = p and p.name or nil

            View:FillLootList(out, raid, bID, pName)
        end,

        rowName = function(n, _, i)
            return n .. "ItemBtn" .. i
        end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            local ui = row._p
            if not row._krtBound then
                if row.RegisterForClicks then
                    row:RegisterForClicks("AnyUp")
                end
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    selectItem(self, button)
                end)
                Frames.SafeSetScript(row, "OnEnter", function(self)
                    onLootRowEnter(self)
                end)
                Frames.SafeSetScript(row, "OnLeave", function(self)
                    onLootRowLeave(self)
                end)
                local itemButton = row.GetName and _G[row:GetName() .. "Item"] or nil
                if itemButton and itemButton.EnableMouse then
                    itemButton:EnableMouse(true)
                end
                if itemButton and itemButton.RegisterForClicks then
                    itemButton:RegisterForClicks("AnyUp")
                end
                if itemButton then
                    itemButton._krtRow = row
                    Frames.SafeSetScript(itemButton, "OnClick", function(_, button)
                        selectItem(row, button)
                    end)
                    Frames.SafeSetScript(itemButton, "OnEnter", function(self)
                        showLootTooltip(self)
                    end)
                    Frames.SafeSetScript(itemButton, "OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                -- Compatibility cleanup: disable legacy shared hover hitbox if present.
                local itemHover = row._itemHover
                if itemHover then
                    if itemHover.Hide then
                        itemHover:Hide()
                    end
                    if itemHover.EnableMouse then
                        itemHover:EnableMouse(false)
                    end
                end

                -- Size the slot background to the button and the icon inset to reveal it.
                if ui.ItemNormalTexture and ui.ItemNormalTexture.SetSize then
                    ui.ItemNormalTexture:SetSize(26, 26)
                end
                if ui.ItemIconTexture and ui.ItemIconTexture.SetSize then
                    ui.ItemIconTexture:SetSize(20, 20)
                end
                row._krtBound = true
            end

            local itemButton = row.GetName and _G[row:GetName() .. "Item"] or nil
            if itemButton then
                itemButton._krtRow = row
                if itemButton.EnableMouse then
                    itemButton:EnableMouse(true)
                end
            end

            local itemHover = row._itemHover
            if itemHover then
                if itemHover.Hide then
                    itemHover:Hide()
                end
                if itemHover.EnableMouse then
                    itemHover:EnableMouse(false)
                end
            end

            -- Preserve a tooltip-ready hyperlink on the pooled row.
            row._itemLink = it.itemLink
            local itemId = tonumber(it.itemId)
            row._itemTooltipLink = it.itemLink or (itemId and itemId > 0 and ("item:" .. itemId) or nil)
            local nameText = it.itemLink or it.itemName or ("[Item " .. (it.itemId or "?") .. "]")
            if it.itemLink then
                ui.Name:SetText(nameText)
            else
                ui.Name:SetText(addon.WrapTextInColorCode(nameText, Colors.NormalizeHexColor(itemColors[(it.itemRarity or 1) + 1])))
            end

            local selectedBoss = module.selectedBoss
            if selectedBoss and tonumber(it.bossNid) == tonumber(selectedBoss) then
                ui.Source:SetText("")
            else
                ui.Source:SetText(it.sourceName or "")
            end
            ui.Source:SetVertexColor(0.86, 0.82, 0.72)

            local winnerClass = it.looterClass or Services.Raid:GetPlayerClass(it.looter)
            local r, g, b = Colors.GetClassColor(winnerClass)
            ui.Winner:SetText(it.looter or "")
            ui.Winner:SetVertexColor(r, g, b)

            local rt = tonumber(it.rollType) or 0
            it.rollType = rt
            ui.Type:SetText(lootTypesColored[rt] or lootTypesColored[4])
            ui.Roll:SetText(it.rollValue or 0)
            ui.Roll:SetVertexColor(0.95, 0.95, 0.95)
            ui.Time:SetText(it.timeFmt)
            ui.Time:SetVertexColor(0.86, 0.82, 0.72)

            local icon = it.itemTexture
            if not icon and it.itemId then
                icon = GetItemIcon(it.itemId)
            end
            if not icon then
                icon = C.RESERVES_ITEM_FALLBACK_ICON
            end
            ui.ItemIconTexture:SetTexture(icon)
            ui.ItemIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end),

        postUpdate = function(n)
            updateSourceHeaderState(n)

            local lootSelCount = MultiSelect.MultiSelectCount(module._msLootCtx)
            local exportBtn = _G[n .. "ExportBtn"]
            local delBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            UIPrimitives.EnableDisable(exportBtn, module.selectedRaid ~= nil)
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, lootSelCount)
            UIPrimitives.EnableDisable(delBtn, (lootSelCount or 0) > 0)
            setPanelTitle(n, Helpers.GetCountContextTitle(L.StrRaidLoot, count, Helpers.GetLootPanelContextLabel(module), nil))
            setFrameHint(n, "EmptyState", Helpers.GetLootEmptyStateText(count, module))
        end,

        sorters = {
            id = function(a, b, asc)
                return CompareLootTie(a, b, asc)
            end,
            source = function(a, b, asc)
                local aSource = strlower(tostring((a and a.sourceName) or ""))
                local bSource = strlower(tostring((b and b.sourceName) or ""))
                if aSource ~= bSource then
                    return CompareValues(aSource, bSource, asc)
                end
                return CompareLootTie(a, b, asc)
            end,
            winner = function(a, b, asc)
                local aWinner = strlower(tostring((a and a.looter) or ""))
                local bWinner = strlower(tostring((b and b.looter) or ""))
                if aWinner ~= bWinner then
                    return CompareValues(aWinner, bWinner, asc)
                end
                return CompareLootTie(a, b, asc)
            end,
            type = function(a, b, asc)
                local aType = tonumber(a and a.rollType) or 0
                local bType = tonumber(b and b.rollType) or 0
                if aType ~= bType then
                    return CompareValues(aType, bType, asc)
                end
                return CompareLootTie(a, b, asc)
            end,
            roll = function(a, b, asc)
                local aRoll = tonumber(a and a.rollValue) or 0
                local bRoll = tonumber(b and b.rollValue) or 0
                if aRoll ~= bRoll then
                    return CompareValues(aRoll, bRoll, asc)
                end
                return CompareLootTie(a, b, asc)
            end,
            time = function(a, b, asc)
                local aTime = tonumber(a and a.time) or 0
                local bTime = tonumber(b and b.time) or 0
                if aTime ~= bTime then
                    return CompareValues(aTime, bTime, asc)
                end
                return CompareLootTie(a, b, asc)
            end,
        },
    }, "selectedItem", "_msLootCtx")

    Loot._ctrl = controller
    ListController.BindListController(Loot, controller)

    sortLoot = function(key)
        if key == "source" and module.selectedBoss then
            return
        end
        controller:Sort(key)
    end

    showLootTooltip = function(widget)
        if not widget then
            return
        end

        local row = widget._krtRow
        if not row then
            row = widget
            -- Climb parents until we find the pooled row carrying tooltip data.
            while row and not (row._itemTooltipLink or row._itemLink) do
                row = row.GetParent and row:GetParent() or nil
            end
        end
        if not row then
            return
        end

        local link = row._itemTooltipLink or row._itemLink
        if not link then
            return
        end

        GameTooltip:SetOwner(widget, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
    end

    do
        local function deleteItem()
            runWithSelectedRaid(function(_, rID)
                local ctx = module._msLootCtx
                local selected = MultiSelect.MultiSelectGetSelected(ctx)
                if not selected or #selected == 0 then
                    return
                end

                local removed = Actions:DeleteLootMany(rID, selected)
                if removed > 0 then
                    MultiSelect.MultiSelectClear(ctx)
                    module.selectedItem = nil
                    triggerSelectionEvent(module, "selectedItem")

                    if Options.IsDebugEnabled() and addon.debug then
                        addon:debug((Diag.D.LogLoggerSelectDeleteItems):format(removed))
                    end
                end
            end)
        end

        function Loot:Delete()
            if MultiSelect.MultiSelectCount(module._msLootCtx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ITEM", L.StrConfirmDeleteItem, deleteItem)
    end

    local function resolveLoggerLootRaidId(source, raidIDOverride)
        if raidIDOverride then
            return raidIDOverride
        end

        -- If the module window is open and browsing an old raid, selectedRaid may
        -- differ from Core.GetCurrentRaid(). Runtime sources must always write
        -- into the current raid session; Logger UI edits target selectedRaid.
        local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
        if isLoggerSource then
            return module.selectedRaid or Core.GetCurrentRaid()
        end
        return Core.GetCurrentRaid() or module.selectedRaid
    end

    local function resolveLoggerLootEntry(raidID, lootNid)
        local raid = raidID and Core.EnsureRaidById(raidID) or nil
        if not raid then
            addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(lootNid)))
            return nil, nil
        end

        Store:EnsureRaid(raid)
        local lootCount = raid.loot and #raid.loot or 0
        local it = Store:GetLoot(raid, lootNid)
        if not it then
            local rawItemMatch, rawItemMatches = Helpers.FindLootByItemId(raid, lootNid)
            if rawItemMatch and addon.error then
                addon:error(Diag.E.LogLoggerLootNidExpected:format(tostring(raidID), tostring(lootNid), tostring(rawItemMatch.itemLink), tonumber(rawItemMatches) or 0))
            end
            addon:error(Diag.E.LogLoggerItemNotFound:format(raidID, tostring(lootNid), lootCount))
            return nil, nil
        end

        return raid, it
    end

    local function applyLoggerLootMutation(raid, it, raidID, lootNid, looter, rollType, rollValue)
        if not looter or looter == "" then
            addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(Diag.W.LogLoggerRollTypeNil:format(raidID, tostring(lootNid), tostring(looter)))
        end

        local currentLooterName = Store._ResolveLootLooterName(raid, it)
        if addon.hasDebug then
            addon:debug(
                Diag.D.LogLoggerLootBefore:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(it.rollType), tostring(it.rollValue))
            )
        end
        if currentLooterName and currentLooterName ~= "" and looter and looter ~= "" and currentLooterName ~= looter then
            addon:warn(Diag.W.LogLoggerLootOverwrite:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(looter)))
        end

        local expectedLooterNid
        local expectedRollType
        local expectedRollValue
        if looter and looter ~= "" then
            local looterNid = Store._ResolveLootLooterNid(raid, looter)
            if not looterNid then
                addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
                return false, nil, nil, nil
            end
            it.looterNid = looterNid
            it.looter = nil
            expectedLooterNid = looterNid
        end
        if tonumber(rollType) then
            it.rollType = tonumber(rollType)
            expectedRollType = tonumber(rollType)
        end
        if tonumber(rollValue) then
            it.rollValue = tonumber(rollValue)
            expectedRollValue = tonumber(rollValue)
        end

        return true, expectedLooterNid, expectedRollType, expectedRollValue
    end

    local function verifyLoggerLootMutation(raidID, lootNid, it, recordedLooterName, expectedLooterNid, expectedRollType, expectedRollValue)
        local ok = true
        if expectedLooterNid and tonumber(it.looterNid) ~= expectedLooterNid then
            ok = false
        end
        if expectedRollType and it.rollType ~= expectedRollType then
            ok = false
        end
        if expectedRollValue and it.rollValue ~= expectedRollValue then
            ok = false
        end
        if not ok then
            addon:error(Diag.E.LogLoggerVerifyFailed:format(raidID, tostring(lootNid), tostring(recordedLooterName), tostring(it.rollType), tostring(it.rollValue)))
            return false
        end

        if addon.hasDebug then
            addon:debug(Diag.D.LogLoggerVerified:format(raidID, tostring(lootNid)))
            if not Core.GetLastBoss() then
                addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(lootNid), tostring(it.itemLink)))
            end
        end
        return true
    end

    function Loot:SetLootEntry(lootNid, looter, rollType, rollValue, source, raidIDOverride)
        local raidID = resolveLoggerLootRaidId(source, raidIDOverride)
        if addon.hasTrace then
            addon:trace(
                Diag.D.LogLoggerLootLogAttempt:format(
                    tostring(source),
                    tostring(raidID),
                    tostring(lootNid),
                    tostring(looter),
                    tostring(rollType),
                    tostring(rollValue),
                    tostring(Core.GetLastBoss())
                )
            )
        end

        local raid, it = resolveLoggerLootEntry(raidID, lootNid)
        if not raid then
            return false
        end

        local ok, expectedLooterNid, expectedRollType, expectedRollValue = applyLoggerLootMutation(raid, it, raidID, lootNid, looter, rollType, rollValue)
        if not ok then
            return false
        end
        controller:Dirty()

        local recordedLooterName = Store._ResolveLootLooterName(raid, it)
        if addon.hasDebug then
            addon:debug(
                Diag.D.LogLoggerLootRecorded:format(
                    tostring(source),
                    raidID,
                    tostring(lootNid),
                    tostring(it.itemLink),
                    tostring(recordedLooterName),
                    tostring(it.rollType),
                    tostring(it.rollValue)
                )
            )
        end

        return verifyLoggerLootMutation(raidID, lootNid, it, recordedLooterName, expectedLooterNid, expectedRollType, expectedRollValue)
    end

    Bus.RegisterCallback(InternalEvents.LoggerLootLogRequest, function(_, request)
        if type(request) ~= "table" then
            addon:error(Diag.E.LogLoggerLootLogRequestPayloadInvalid:format(type(request)))
            return
        end
        local raidId = request.raidId or request.raidID
        local lootNid = request.lootNid or request.itemID
        request.ok = Loot:SetLootEntry(lootNid, request.looter, request.rollType, request.rollValue, request.source, raidId) == true
    end)

    local function reset()
        controller:Dirty()
    end
    Bus.RegisterCallbacks({
        InternalEvents.LoggerSelectRaid,
        InternalEvents.LoggerSelectBoss,
        InternalEvents.LoggerSelectPlayer,
        InternalEvents.LoggerSelectBossPlayer,
        InternalEvents.RaidLootUpdate,
    }, reset)
    Bus.RegisterCallback(InternalEvents.LoggerSelectItem, function()
        controller:Touch()
    end)
end

local function ensurePopupRefs(box)
    if not box then
        return nil
    end
    if box.refs then
        return box.refs
    end
    if type(box.BindUI) == "function" then
        box:BindUI()
    end
    return box.refs
end

local function makePopupBox(moduleName, frameName, cfg)
    local Box = module[moduleName] or {}
    module[moduleName] = Box
    Box._ui = Box._ui or {
        Loaded = false,
        Bound = false,
        Localized = false,
        Dirty = true,
        Reason = nil,
        FrameName = nil,
    }
    local BoxUI = Box._ui
    local getFrame = makeModuleFrameGetter(Box, frameName)
    local suffixes = cfg.refSuffixes
    local saveRef, cancelRef = cfg.saveRef, cfg.cancelRef or "cancelBtn"
    local enterRefs = cfg.enterRefs or {}
    local localizeMap = cfg.localizeMap
    local onShow, onHide = cfg.onShow, cfg.onHide

    function Box.AcquireRefs(frame)
        local refs = {}
        for i = 1, #suffixes do
            local s = suffixes[i]
            refs[s:sub(1, 1):lower() .. s:sub(2)] = Frames.Ref(frame, s)
        end
        return refs
    end

    local function bindHandlers(_, frame, refs)
        if not frame or frame._krtBound then
            return
        end
        if refs[saveRef] then
            Frames.SafeSetScript(refs[saveRef], "OnClick", function()
                Box._doSave()
            end)
        end
        if refs[cancelRef] then
            Frames.SafeSetScript(refs[cancelRef], "OnClick", function()
                Box:Hide()
            end)
        end
        for i = 1, #enterRefs do
            if refs[enterRefs[i]] then
                Frames.SafeSetScript(refs[enterRefs[i]], "OnEnterPressed", function()
                    Box._doSave()
                end)
            end
        end
        frame._krtBound = true
    end

    function Box:LocalizeUI(_, _, refs)
        for key, text in pairs(localizeMap) do
            if refs[key] then
                refs[key]:SetText(text)
            end
        end
    end

    function Box:OnLoad(frame)
        BoxUI.FrameName = Frames.InitModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = onShow and function()
                onShow(Box)
            end or nil,
            hookOnHide = onHide and function()
                onHide(Box)
            end or nil,
        }) or BoxUI.FrameName
        BoxUI.Loaded = BoxUI.FrameName ~= nil
    end

    local refreshFn = cfg.refresh
    UIScaffold.DefineModuleUi({
        module = Box,
        getFrame = getFrame,
        acquireRefs = Box.AcquireRefs,
        bind = bindHandlers,
        localize = function(fn, frame, refs)
            Box:LocalizeUI(fn, frame, refs)
        end,
        onLoad = function(frame)
            Box:OnLoad(frame)
            return BoxUI.FrameName
        end,
        refresh = refreshFn and function()
            refreshFn(Box)
        end or nil,
    })

    Box._doSave = function() end
    return Box, BoxUI
end

-- Add/edit boss popup (time/mode normalization).
do
    local Box, BoxUI = makePopupBox("BossBox", "KRTLoggerBossBox", {
        refSuffixes = { "Title", "Name", "Difficulty", "Time", "NameStr", "DifficultyStr", "TimeStr", "SaveBtn", "CancelBtn" },
        saveRef = "saveBtn",
        enterRefs = { "name", "difficulty", "time" },
        localizeMap = {
            nameStr = L.StrName,
            difficultyStr = L.StrDifficulty,
            timeStr = L.StrTime,
            saveBtn = L.BtnSave,
            cancelBtn = L.BtnCancel,
        },
        onShow = function(b)
            b:RequestRefresh("show")
        end,
        onHide = function(b)
            b:CancelAddEdit()
        end,
        refresh = function(b)
            b:RefreshUI()
        end,
    })
    local Store = module.Store

    local isEdit = false
    local tooltipsBound = false
    local raidData, bossData, tempDate = {}, {}, {}
    local editBossNid

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    fillBossBox = function()
        local rID, bID = module.selectedRaid, module.selectedBoss
        if not (rID and bID) then
            return
        end

        raidData = Store:GetRaid(rID)
        if not raidData then
            return
        end

        bossData = Store:GetBoss(raidData, bID)
        if not bossData then
            return
        end

        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        local timeBox = refs and refs.time
        local difficultyBox = refs and refs.difficulty
        if not (nameBox and timeBox and difficultyBox) then
            return
        end

        nameBox:SetText(bossData.name or "")

        local bossTime = bossData.time or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        timeBox:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        difficultyBox:SetText((mode == "h") and "h" or "n")

        editBossNid = bossData and bossData.bossNid or nil
        isEdit = true
        Box:Toggle()
    end

    Box._doSave = function()
        local rID = module.selectedRaid
        if not rID then
            return
        end

        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        local difficultyBox = refs and refs.difficulty
        local timeBox = refs and refs.time
        if not (nameBox and difficultyBox and timeBox) then
            return
        end

        local name = Strings.TrimText(nameBox:GetText())
        local modeT = Strings.NormalizeLower(difficultyBox:GetText())
        local bTime = Strings.TrimText(timeBox:GetText())

        name = (name == "") and TRASH_MOB_NAME or name
        if not isTrashMobName(name) and (modeT ~= "h" and modeT ~= "n") then
            addon:error(L.ErrBossDifficulty)
            return
        end

        local h, m = bTime:match("^(%d+):(%d+)$")
        h, m = tonumber(h), tonumber(m)
        if not (h and m and addon.WithinRange(h, 0, 23) and addon.WithinRange(m, 0, 59)) then
            addon:error(L.ErrBossTime)
            return
        end

        local _, month, day, year = CalendarGetDate()
        local killDate = { day = day, month = month, year = year, hour = h, min = m }
        local mode = (modeT == "h") and "h" or "n"

        local bossNid = isEdit and editBossNid or nil
        local savedNid = module.Actions:UpsertBossKill(rID, bossNid, name, time(killDate), mode)
        if not savedNid then
            return
        end

        Box:Hide()
        resetSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function Box:CancelAddEdit()
        local refs = ensurePopupRefs(Box)
        Frames.ResetEditBox(refs and refs.name)
        Frames.ResetEditBox(refs and refs.difficulty)
        Frames.ResetEditBox(refs and refs.time)
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    function Box:RefreshUI()
        local refs = ensurePopupRefs(Box)
        local title = refs and refs.title
        if not title then
            return
        end

        if not tooltipsBound then
            Frames.SetTooltip(refs.name, L.StrBossNameHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(refs.difficulty, L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(refs.time, L.StrBossTimeHelp, "ANCHOR_RIGHT")
            tooltipsBound = true
        end

        UIPrimitives.SetText(title, L.StrEditBoss, L.StrAddBoss, isEdit)
    end

    function Box:Refresh()
        return self:RefreshUI()
    end
end

-- Add attendee popup.
do
    local Box = makePopupBox("AttendeesBox", "KRTLoggerPlayerBox", {
        refSuffixes = { "Title", "NameStr", "AddBtn", "CancelBtn", "Name" },
        saveRef = "addBtn",
        enterRefs = { "name" },
        localizeMap = {
            title = L.StrAddPlayer,
            nameStr = L.StrName,
            addBtn = L.BtnAdd,
            cancelBtn = L.BtnCancel,
        },
        onShow = function(b)
            local refs = ensurePopupRefs(b)
            Frames.ResetEditBox(refs and refs.name)
        end,
        onHide = function(b)
            local refs = ensurePopupRefs(b)
            Frames.ResetEditBox(refs and refs.name)
        end,
    })

    Box._doSave = function()
        local rID, bID = module.selectedRaid, module.selectedBoss
        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        if not nameBox then
            return
        end
        local name = Strings.TrimText(nameBox:GetText())
        if module.Actions:AddBossAttendee(rID, bID, name) then
            Box:Toggle()
            triggerSelectionEvent(module, "selectedBoss")
        end
    end
end
