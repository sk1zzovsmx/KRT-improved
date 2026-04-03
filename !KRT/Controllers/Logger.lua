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
local Events = feature.Events or addon.Events or {}
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
local Services = feature.Services or addon.Services or {}

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

local _G = _G
local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local tconcat = table.concat
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber
local strlower = string.lower

local SetSelectedRaid
local deleteSelectedAttendees
local setFrameLabel
local setPanelTitle
local getSelectedRaidRecord
local getSelectedRaidContextLabel
local getSelectedBossContextLabel
local getSelectedPlayerContextLabel
local buildLootPanelContextLabel
local setFrameHint

local function getRaidQueries()
    if Core.GetRaidQueries then
        return Core.GetRaidQueries()
    end
    return nil
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

addon.Controllers = addon.Controllers or {}
addon.Controllers.Logger = addon.Controllers.Logger or {}
local module = addon.Controllers.Logger
module._ui = module._ui or {
    Loaded = false,
    Bound = false,
    Localized = false,
    Dirty = true,
    Reason = nil,
    FrameName = nil,
}

-- Logger frame module.
do
    -- ----- Internal state ----- --
    local UI = module._ui
    local getFrame = makeModuleFrameGetter(module, "KRTLogger")
    -- Import service modules (extracted to Services/Logger/).
    local LoggerSvc = addon.Services.Logger
    local Store = LoggerSvc.Store
    local View = LoggerSvc.View
    local Actions = LoggerSvc.Actions
    local Helpers = LoggerSvc.Helpers

    module.Store = Store
    module.View = View
    module.Actions = Actions
    module.Helpers = Helpers

    -- Bind controller reference so Actions:Commit() can validate selections.
    Actions:BindController(module, triggerSelectionEvent)

    -- ----- Private helpers ----- --

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

    getSelectedRaidContextLabel = function()
        local raid = getSelectedRaidRecord()
        local zone = raid and raid.zone or nil
        local difficulty = raid and View:GetRaidDifficultyLabel(raid) or ""
        if zone and zone ~= "" and difficulty ~= "" then
            return ("%s %s"):format(zone, difficulty)
        end
        if zone and zone ~= "" then
            return zone
        end
        if difficulty ~= "" then
            return difficulty
        end
        return nil
    end

    getSelectedBossContextLabel = function()
        local raid = getSelectedRaidRecord()
        local boss = (raid and module.selectedBoss) and Store:GetBoss(raid, module.selectedBoss) or nil
        local name
        local mode
        if not boss then
            return nil
        end
        name = boss.name
        if not name or name == "" then
            name = L.StrTrashMob
        end
        mode = View:GetBossModeLabel(boss)
        if mode and mode ~= "" then
            return ("%s %s"):format(name, mode)
        end
        return name
    end

    getSelectedPlayerContextLabel = function(playerNid)
        local raid = getSelectedRaidRecord()
        local player = (raid and playerNid) and Store:GetPlayer(raid, playerNid) or nil
        if player and player.name and player.name ~= "" then
            return L.StrLoggerLabelPlayer:format(player.name)
        end
        return nil
    end

    buildLootPanelContextLabel = function()
        local parts = {}
        local bossLabel = getSelectedBossContextLabel()
        local playerLabel = getSelectedPlayerContextLabel(module.selectedBossPlayer or module.selectedPlayer)

        if bossLabel and bossLabel ~= "" then
            parts[#parts + 1] = bossLabel
        end
        if playerLabel and playerLabel ~= "" then
            parts[#parts + 1] = playerLabel
        end
        if #parts > 0 then
            return tconcat(parts, " | ")
        end
        return getSelectedRaidContextLabel()
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
    local TAB_HISTORY = "history"
    local TAB_EXPORT = "export"
    local EXPORT_TAB_ENABLED = false

    module.activeTab = module.activeTab or TAB_HISTORY

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
    module._msRaidScopeExport = module._msRaidScopeExport or "LoggerExportRaids"
    module._msBossScope = module._msBossScope or "LoggerBosses"
    module._msBossAttScope = module._msBossAttScope or "LoggerBossAttendees"
    module._msRaidAttScope = module._msRaidAttScope or "LoggerRaidAttendees"
    module._msLootScope = module._msLootScope or "LoggerLoot"

    local MS_SCOPE_RAID_HISTORY = module._msRaidScopeHistory
    local MS_SCOPE_RAID_EXPORT = module._msRaidScopeExport
    local MS_SCOPE_BOSS = module._msBossScope
    local MS_SCOPE_BOSSATT = module._msBossAttScope
    local MS_SCOPE_RAIDATT = module._msRaidAttScope
    local MS_SCOPE_LOOT = module._msLootScope

    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_RAID_HISTORY, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_RAID_EXPORT, { allowMulti = false, allowRange = false })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_BOSS, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_BOSSATT, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_RAIDATT, { allowMulti = true, allowRange = true })
    MultiSelect.MultiSelectSetModifierPolicy(MS_SCOPE_LOOT, { allowMulti = true, allowRange = true })
    local function normalizeTabName(tabName)
        if tabName == TAB_EXPORT and EXPORT_TAB_ENABLED then
            return TAB_EXPORT
        end
        return TAB_HISTORY
    end

    local function updateTabUi()
        local refs = module.refs
        if not refs then
            return
        end

        module.activeTab = normalizeTabName(module.activeTab)

        local isHistory = (module.activeTab ~= TAB_EXPORT)
        local activeTabId = isHistory and 1 or 2

        local historyFrames = {
            refs.history,
        }
        local exportFrames = {
            refs.export,
        }

        if refs.exportTabBtn then
            Frames.SetShown(refs.exportTabBtn, EXPORT_TAB_ENABLED)
        end

        -- Hard switch on concrete frames to avoid any residual visual overlap.
        for i = 1, #historyFrames do
            Frames.SetShown(historyFrames[i], false)
        end
        for i = 1, #exportFrames do
            Frames.SetShown(exportFrames[i], false)
        end

        local visibleGroup = isHistory and historyFrames or exportFrames
        for i = 1, #visibleGroup do
            Frames.SetShown(visibleGroup[i], true)
        end

        local frame = module.frame or getFrame()
        if frame and PanelTemplates_SetTab then
            PanelTemplates_SetTab(frame, activeTabId)
        else
            if refs.historyTabBtn and refs.historyTabBtn.UnlockHighlight then
                refs.historyTabBtn:UnlockHighlight()
            end
            if refs.exportTabBtn and refs.exportTabBtn.UnlockHighlight then
                refs.exportTabBtn:UnlockHighlight()
            end
            if isHistory and refs.historyTabBtn and refs.historyTabBtn.LockHighlight then
                refs.historyTabBtn:LockHighlight()
            elseif refs.exportTabBtn and refs.exportTabBtn.LockHighlight then
                refs.exportTabBtn:LockHighlight()
            end
        end

        if not isHistory then
            if refs.bossBox and refs.bossBox.IsShown and refs.bossBox:IsShown() then
                refs.bossBox:Hide()
            end
            if refs.attendeesBox and refs.attendeesBox.IsShown and refs.attendeesBox:IsShown() then
                refs.attendeesBox:Hide()
            end
            if module.Export and module.Export.EnsureCsvFresh then
                module.Export:EnsureCsvFresh()
            end
        end
    end

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        clearSelection(module, "selectedBoss", MS_CTX_BOSS)
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
        clearSelection(module, "selectedItem", MS_CTX_LOOT)
    end

    deleteSelectedAttendees = function(ctx, deleteFn, onRemoved)
        module:Run(function(_, rID)
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
        local raidAttendeesCtrl = module.RaidAttendees and module.RaidAttendees._ctrl
        if raidAttendeesCtrl and raidAttendeesCtrl.Dirty then
            raidAttendeesCtrl:Dirty()
        end

        local bossAttendeesCtrl = module.BossAttendees and module.BossAttendees._ctrl
        if bossAttendeesCtrl and bossAttendeesCtrl.Dirty then
            bossAttendeesCtrl:Dirty()
        end

        local lootCtrl = module.Loot and module.Loot._ctrl
        if lootCtrl and lootCtrl.Dirty then
            lootCtrl:Dirty()
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
    function module:NeedRaid()
        local rID = module.selectedRaid
        local raid = rID and Store:GetRaid(rID) or nil
        return raid, rID
    end

    function module:NeedBoss(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then
            return nil
        end
        local bNid = module.selectedBoss
        if not bNid then
            return nil
        end
        return Store:GetBoss(raid, bNid)
    end

    function module:NeedLoot(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then
            return nil
        end
        local lNid = module.selectedItem
        if not lNid then
            return nil
        end
        return Store:GetLoot(raid, lNid)
    end

    function module:Run(fn, refreshEvent)
        local raid, rID = module:NeedRaid()
        if not raid then
            return
        end
        fn(raid, rID)
        if refreshEvent ~= false then
            Bus.TriggerEvent(refreshEvent or InternalEvents.LoggerSelectRaid, module.selectedRaid)
        end
    end

    function module:ResetSelections()
        clearSelections()
    end

    function module:SetTab(tabName)
        module.activeTab = normalizeTabName(tabName)
        updateTabUi()
        if module.activeTab == TAB_EXPORT and module.Export and module.Export._csvDirty == true and module.Export.RefreshCsv then
            module.Export:RefreshCsv()
        end
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
                module:SetTab(module.activeTab)
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
        if refs.historyTabBtn and not refs.historyTabBtn._krtBound then
            Frames.SafeSetScript(refs.historyTabBtn, "OnClick", function()
                module:SetTab(TAB_HISTORY)
            end)
            refs.historyTabBtn._krtBound = true
            if refs.historyTabBtn.SetID then
                refs.historyTabBtn:SetID(1)
            end
        end
        if refs.exportTabBtn and not refs.exportTabBtn._krtBound then
            Frames.SafeSetScript(refs.exportTabBtn, "OnClick", function()
                module:SetTab(TAB_EXPORT)
            end)
            refs.exportTabBtn._krtBound = true
            if refs.exportTabBtn.SetID then
                refs.exportTabBtn:SetID(2)
            end
        end
        if refs.historyTabBtn then
            refs.historyTabBtn:SetText(L.StrHistoryTab)
        end
        if refs.exportTabBtn then
            refs.exportTabBtn:SetText(L.StrExportTab)
        end
        if PanelTemplates_SetNumTabs then
            PanelTemplates_SetNumTabs(frame, EXPORT_TAB_ENABLED and 2 or 1)
        end

        ensureSubmoduleOnLoad(module.Raids, refs.raids)
        ensureSubmoduleOnLoad(module.Boss, refs.bosses)
        ensureSubmoduleOnLoad(module.Loot, refs.loot)
        ensureSubmoduleOnLoad(module.RaidAttendees, refs.raidAttendees)
        ensureSubmoduleOnLoad(module.BossAttendees, refs.bossAttendees)
        ensureSubmoduleOnLoad(module.BossBox, refs.bossBox)
        ensureSubmoduleOnLoad(module.AttendeesBox, refs.attendeesBox)

        if EXPORT_TAB_ENABLED then
            ensureSubmoduleOnLoad(module.ExportRaids, refs.exportRaids)
            ensureSubmoduleOnLoad(module.Export, refs.export)
        end

        module:SetTab(module.activeTab)
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
        module:SetTab(module.activeTab)
    end

    function module:Refresh()
        return self:RefreshUI()
    end

    -- Selectors
    function module:SelectRaid(btn, button, opts)
        if button and button ~= "LeftButton" then
            return
        end
        local raidNid = btn and btn.GetID and btn:GetID()
        if not raidNid then
            return
        end
        local raidIndex = Helpers:GetRaidIndexByNid(raidNid)
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
                return Helpers:GetRaidIndexByNid(nid)
            end,
            isClickedFocused = function(clickedNid)
                return Helpers:GetRaidNidByIndex(module.selectedRaid) == clickedNid
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

    function module:SelectBoss(btn, button)
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
    function module:SelectBossPlayer(btn, button)
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

    function module:SelectPlayer(btn, button)
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
            module.Loot:Log(lootNid, nil, rollType, nil, "LOGGER_EDIT_ROLLTYPE")
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

        function module:SelectItem(btn, button)
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

        -- Hover sync: keep selection highlight persistent while hover uses default Button behavior.
        function module:OnLootRowEnter(row)
            -- No-op: persistent selection is rendered via overlay textures (addon.UIRowVisuals).
            -- Leave native hover highlight behavior intact.
        end

        function module:OnLootRowLeave(row)
            -- No-op: persistent selection is rendered via overlay textures.
        end

        local function findLoggerPlayer(normalizedName, raid, bossKill)
            if raid and raid.players then
                for _, p in ipairs(raid.players) do
                    if normalizedName == Strings.NormalizeLower(p.name) then
                        return p.name
                    end
                end
            end
            if bossKill and bossKill.players then
                for i = 1, #bossKill.players do
                    local playerNid = tonumber(bossKill.players[i])
                    local playerName = playerNid and Store:ResolvePlayerNameByNid(raid, playerNid) or nil
                    if playerName and normalizedName == Strings.NormalizeLower(playerName) then
                        return playerName
                    end
                end
            end
        end

        local function validateRollValue(_, text)
            local value = text and tonumber(text)
            if not value or value < 0 then
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
            local winner = findLoggerPlayer(name, raid, bossKill)
            if not winner then
                addon:error(L.ErrLoggerWinnerNotFound:format(rawText))
                return
            end

            module.Loot:Log(self.lootNid, winner, nil, nil, "LOGGER_EDIT_WINNER")
        end, function(self)
            self.raidId = module.selectedRaid
            self.lootNid = module.selectedItem
        end)

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp, function(self, text)
            module.Loot:Log(self.lootNid, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
        end, function(self)
            self.lootNid = module.selectedItem
        end, validateRollValue)
    end
end

-- Raids list.
do
    module.Raids = module.Raids or {}
    local Raids = module.Raids
    local Store = module.Store
    local Helpers = module.Helpers
    local controller
    controller = ListController.MakeListController({
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
                Frames.SafeSetScript(_G[n .. "HeaderNum"], "OnClick", function()
                    Raids:Sort("id")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderDate"], "OnClick", function()
                    Raids:Sort("date")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderZone"], "OnClick", function()
                    Raids:Sort("zone")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderSize"], "OnClick", function()
                    Raids:Sort("size")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raidStore = Core.GetRaidStoreOrNil("Logger.Raids.GetData", { "GetAllRaids", "GetRaidByIndex" })
            local raids = raidStore and raidStore:GetAllRaids() or {}
            local queries = getRaidQueries()
            for i = 1, #raids do
                local r = raidStore and raidStore:GetRaidByIndex(i) or Core.EnsureRaidById(i)
                if r then
                    local summary = queries and queries.GetRaidSummary and queries:GetRaidSummary(r) or nil
                    local it = {}
                    it.id = tonumber(r.raidNid)
                    it.seq = i
                    it.zone = r.zone
                    it.size = (summary and summary.size) or r.size
                    it.difficulty = tonumber((summary and summary.difficulty) or r.difficulty)
                    local mode = it.difficulty and ((it.difficulty == 3 or it.difficulty == 4) and "H" or "N") or "?"
                    it.sizeLabel = tostring(it.size or "") .. mode
                    it.date = (summary and summary.startTime) or r.startTime
                    it.dateFmt = date("%d/%m/%Y %H:%M", it.date)
                    out[i] = it
                end
            end
        end,

        rowName = function(n, _, i)
            return n .. "RaidBtn" .. i
        end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    module:SelectRaid(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            ui.ID:SetText(it.seq or it.id)
            ui.Date:SetText(it.dateFmt)
            ui.Zone:SetText(it.zone)
            ui.Size:SetText(it.sizeLabel or it.size)
        end),

        highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module._msRaidCtx, id)
        end,
        focusId = function()
            local selected = module.selectedRaid
            return selected and Core.GetRaidNidById(selected) or nil
        end,
        focusKey = function()
            local selected = module.selectedRaid
            local raidNid = selected and Core.GetRaidNidById(selected) or nil
            return tostring(raidNid or "nil")
        end,
        highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module._msRaidCtx)
        end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msRaidCtx), MultiSelect.MultiSelectCount(module._msRaidCtx))
        end,

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
            setPanelTitle(n, Helpers:BuildCountTitle(L.StrRaidsList, count))
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
    })

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
            module:ResetSelections()
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
            module:ResetSelections()
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
        module:ResetSelections()
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
            module:ResetSelections()
        end

        if reason == "sync" then
            local raid = module.selectedRaid and Store:GetRaid(module.selectedRaid) or nil
            if raid and Store.InvalidateIndexes then
                Store:InvalidateIndexes(raid)
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

-- Export raids list.
do
    module.ExportRaids = module.ExportRaids or {}
    local ExportRaids = module.ExportRaids
    local Helpers = module.Helpers

    local controller
    controller = ListController.MakeListController({
        keyName = "ExportRaidsList",
        poolTag = "logger-export-raids",
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

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "HeaderNum"], "OnClick", function()
                    ExportRaids:Sort("id")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderDate"], "OnClick", function()
                    ExportRaids:Sort("date")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderZone"], "OnClick", function()
                    ExportRaids:Sort("zone")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderSize"], "OnClick", function()
                    ExportRaids:Sort("size")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raidStore = Core.GetRaidStoreOrNil("Logger.ExportRaids.GetData", { "GetAllRaids", "GetRaidByIndex" })
            local raids = raidStore and raidStore:GetAllRaids() or {}
            local queries = getRaidQueries()
            for i = 1, #raids do
                local raid = raidStore and raidStore:GetRaidByIndex(i) or Core.EnsureRaidById(i)
                if raid then
                    local summary = queries and queries.GetRaidSummary and queries:GetRaidSummary(raid) or nil
                    local it = {}
                    it.id = tonumber(raid.raidNid)
                    it.seq = i
                    it.zone = raid.zone
                    it.size = (summary and summary.size) or raid.size
                    it.difficulty = tonumber((summary and summary.difficulty) or raid.difficulty)
                    local mode = it.difficulty and ((it.difficulty == 3 or it.difficulty == 4) and "H" or "N") or "?"
                    it.sizeLabel = tostring(it.size or "") .. mode
                    it.date = (summary and summary.startTime) or raid.startTime
                    it.dateFmt = date("%d/%m/%Y %H:%M", it.date)
                    out[i] = it
                end
            end
        end,

        rowName = function(n, _, i)
            return n .. "RaidBtn" .. i
        end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    module:SelectRaid(self, button, {
                        ordered = controller.data,
                        modifierScope = module._msRaidScopeExport,
                        forceSingle = true,
                        allowDeselect = false,
                    })
                end)
                row._krtBound = true
            end
            local ui = row._p
            ui.ID:SetText(it.seq or it.id)
            ui.Date:SetText(it.dateFmt)
            ui.Zone:SetText(it.zone)
            ui.Size:SetText(it.sizeLabel or it.size)
        end),

        highlightId = function()
            local selected = module.selectedRaid
            return selected and Core.GetRaidNidById(selected) or nil
        end,
        focusId = function()
            local selected = module.selectedRaid
            return selected and Core.GetRaidNidById(selected) or nil
        end,
        focusKey = function()
            local selected = module.selectedRaid
            local raidNid = selected and Core.GetRaidNidById(selected) or nil
            return tostring(raidNid or "nil")
        end,
        highlightDebugTag = "LoggerExportSelect",
        highlightDebugInfo = function()
            local selected = module.selectedRaid
            local raidNid = selected and Core.GetRaidNidById(selected) or nil
            return ("selectedRaidNid=%s"):format(tostring(raidNid))
        end,

        postUpdate = function(n)
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, Helpers:BuildCountTitle(L.StrRaidsList, count))
            setFrameHint(n, "EmptyState", count == 0 and L.StrLoggerEmptyExportRaids or nil)
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
    })

    ExportRaids._ctrl = controller
    ListController.BindListController(ExportRaids, controller)

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function(_, _, reason)
        if reason == "sync" then
            controller:Dirty()
        else
            controller:Touch()
        end
    end)
    Bus.RegisterCallback(InternalEvents.RaidCreate, function()
        controller:Dirty()
    end)
end

-- Export panel (CSV preview).
do
    module.Export = module.Export or {}
    local Export = module.Export
    local Store = module.Store
    local View = module.View
    local Helpers = module.Helpers

    local function updateCsvTitle(frame)
        local frameName = frame and frame.GetName and frame:GetName() or nil
        local titleText = Helpers:BuildContextTitle(L.StrRaidCsvTitle, getSelectedRaidContextLabel(), nil)
        setFrameLabel(frameName, "CsvTitle", titleText)
        setFrameHint(frameName, "CsvEmptyState", Helpers:BuildCsvEmptyStateText(nil, module.selectedRaid ~= nil))
    end

    local function getScrollBarInset(scrollFrame)
        if not scrollFrame then
            return 4
        end

        local scrollBar
        if scrollFrame.GetName then
            scrollBar = _G[(scrollFrame:GetName() or "") .. "ScrollBar"]
        end
        if not scrollBar then
            scrollBar = scrollFrame.ScrollBar
        end
        if not (scrollBar and scrollBar.GetWidth) then
            return 4
        end

        local width = scrollBar:GetWidth() or 0
        if width < 0 then
            width = 0
        end
        return width + 4
    end

    local function setCsvEditBoxLayout(editBox, scrollFrame)
        if not editBox then
            return
        end

        local minWidth = 180
        local rightInset = getScrollBarInset(scrollFrame)
        if scrollFrame and scrollFrame.GetWidth then
            local frameWidth = scrollFrame:GetWidth() or 0
            local desiredWidth = frameWidth - rightInset
            if desiredWidth > minWidth then
                minWidth = desiredWidth
            end
        end
        if editBox.SetWidth then
            editBox:SetWidth(minWidth)
        end

        local minHeight = 200
        if scrollFrame and scrollFrame.GetHeight then
            minHeight = scrollFrame:GetHeight() or minHeight
        end
        if minHeight < 120 then
            minHeight = 120
        end
        local textHeight = editBox.GetStringHeight and editBox:GetStringHeight() or 0
        local desiredHeight = textHeight + 24
        if desiredHeight < minHeight then
            desiredHeight = minHeight
        end
        if editBox.SetHeight then
            editBox:SetHeight(desiredHeight)
        end
        if scrollFrame and scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
    end

    local function setCsvSelectionState(editBox, csvValue)
        if not editBox then
            return
        end

        addon.CancelTimer(module._exportCsvSelectHandle, true)
        module._exportCsvSelectHandle = nil

        local refs = module.refs
        local exportFrame = refs and refs.export or nil
        local isVisible = module.activeTab == "export" and exportFrame and exportFrame.IsShown and exportFrame:IsShown()
        if not isVisible then
            if editBox.ClearFocus then
                editBox:ClearFocus()
            end
            return
        end

        if editBox.EnableKeyboard then
            editBox:EnableKeyboard(true)
        end

        local selectEnd = string.len(csvValue or "")
        local attempts = 0
        local maxAttempts = 4
        local delaySeconds = 0.05

        local function applySelection()
            local nowRefs = module.refs
            local nowExport = nowRefs and nowRefs.export or nil
            local stillVisible = module.activeTab == "export" and nowExport and nowExport.IsShown and nowExport:IsShown()
            if not stillVisible then
                module._exportCsvSelectHandle = nil
                return
            end

            attempts = attempts + 1

            if editBox.SetFocus then
                editBox:SetFocus()
            end
            if editBox.SetCursorPosition then
                editBox:SetCursorPosition(0)
            end
            if editBox.HighlightText then
                editBox:HighlightText(0, selectEnd)
            end

            if attempts < maxAttempts then
                module._exportCsvSelectHandle = addon.NewTimer(delaySeconds, applySelection)
            else
                module._exportCsvSelectHandle = nil
            end
        end

        applySelection()
    end

    local function hideCsvEditBoxChrome(editBox)
        if not (editBox and editBox.GetName) then
            return
        end

        local name = editBox:GetName()
        if not name then
            return
        end

        local left = _G[name .. "Left"]
        if left and left.Hide then
            left:Hide()
            if left.SetAlpha then
                left:SetAlpha(0)
            end
        end

        local middle = _G[name .. "Middle"]
        if middle and middle.Hide then
            middle:Hide()
            if middle.SetAlpha then
                middle:SetAlpha(0)
            end
        end

        local right = _G[name .. "Right"]
        if right and right.Hide then
            right:Hide()
            if right.SetAlpha then
                right:SetAlpha(0)
            end
        end

        if editBox.GetRegions then
            local regionCount = editBox:GetNumRegions() or 0
            for i = 1, regionCount do
                local region = select(i, editBox:GetRegions())
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    if region.Hide then
                        region:Hide()
                    end
                    if region.SetAlpha then
                        region:SetAlpha(0)
                    end
                end
            end
        end
    end

    local function hideCsvScrollFrameChrome(scrollFrame)
        if not (scrollFrame and scrollFrame.GetRegions) then
            return
        end

        local regionCount = scrollFrame:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, scrollFrame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                if region.Hide then
                    region:Hide()
                end
                if region.SetAlpha then
                    region:SetAlpha(0)
                end
            end
        end
    end

    Export._csvDirty = Export._csvDirty ~= false

    function Export:IsCsvVisible()
        local refs = module.refs
        local exportFrame = refs and refs.export or nil
        local parentFrame = module.frame or _G.KRTLogger
        if not (exportFrame and exportFrame.IsShown and exportFrame:IsShown()) then
            return false
        end
        if not (parentFrame and parentFrame.IsShown and parentFrame:IsShown()) then
            return false
        end
        return module.activeTab == TAB_EXPORT
    end

    function Export:MarkCsvDirty()
        self._csvDirty = true
    end

    function Export:EnsureCsvFresh(force)
        if not self:IsCsvVisible() then
            return false
        end
        if force ~= true and self._csvDirty ~= true then
            return false
        end
        self:RefreshCsv()
        return true
    end

    function Export:OnLoad(frame)
        if not frame then
            return
        end

        local frameName = frame.GetName and frame:GetName() or nil
        if not frameName then
            return
        end

        updateCsvTitle(frame)

        local csvScrollFrame = _G[frameName .. "CsvScrollFrame"]
        hideCsvScrollFrameChrome(csvScrollFrame)

        local csvText = _G[frameName .. "CsvText"]
        if csvText and not csvText._krtBound then
            csvText:SetAutoFocus(false)
            csvText:SetMultiLine(true)
            csvText:SetTextInsets(6, 6, 6, 6)
            csvText:SetJustifyH("LEFT")
            csvText:SetJustifyV("TOP")
            if ChatFontNormal then
                csvText:SetFontObject(ChatFontNormal)
            end
            Frames.SafeSetScript(csvText, "OnEscapePressed", function(self)
                self:ClearFocus()
            end)
            Frames.SafeSetScript(csvText, "OnTextChanged", function(self, userInput)
                if not userInput then
                    return
                end
                self:SetText(self._krtCsvText or "")
                if self.HighlightText then
                    self:HighlightText(0, string.len(self._krtCsvText or ""))
                end
            end)
            Frames.SafeSetScript(csvText, "OnEditFocusGained", function(self)
                Export:EnsureCsvFresh(true)
                hideCsvEditBoxChrome(self)
                if self.HighlightText then
                    self:HighlightText(0, string.len(self._krtCsvText or ""))
                end
            end)
            hideCsvEditBoxChrome(csvText)
            csvText._krtBound = true
        end
    end

    function Export:RefreshCsv()
        local refs = module.refs
        updateCsvTitle(refs and refs.export or nil)
        local csvText = refs and refs.exportCsvText or nil
        if not csvText then
            return
        end

        local raidId = module.selectedRaid
        local raid = raidId and Store:GetRaid(raidId) or nil
        local csvValue = View:BuildRaidCsv(raid, raidId) or ""
        self._csvDirty = false
        csvText._krtCsvText = csvValue
        csvText:SetText(csvValue)
        setFrameHint(refs and refs.export and refs.export:GetName() or nil, "CsvEmptyState", Helpers:BuildCsvEmptyStateText(csvValue, module.selectedRaid ~= nil))
        hideCsvEditBoxChrome(csvText)
        hideCsvScrollFrameChrome(refs and refs.exportCsvScrollFrame or nil)
        setCsvEditBoxLayout(csvText, refs and refs.exportCsvScrollFrame or nil)
        setCsvSelectionState(csvText, csvValue)
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function()
        Export:MarkCsvDirty()
        Export:EnsureCsvFresh()
    end)
    Bus.RegisterCallback(InternalEvents.RaidLootUpdate, function()
        Export:MarkCsvDirty()
        Export:EnsureCsvFresh()
    end)
    Bus.RegisterCallback(InternalEvents.RaidCreate, function()
        Export:MarkCsvDirty()
        Export:EnsureCsvFresh()
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

    local controller
    controller = ListController.MakeListController({
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
                    Boss:Edit()
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
            local raid = module:NeedRaid()
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
                    module:SelectBoss(self, button)
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

        highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module._msBossCtx, id)
        end,
        focusId = function()
            return module.selectedBoss
        end,
        focusKey = function()
            return tostring(module.selectedBoss or "nil")
        end,
        highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module._msBossCtx)
        end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msBossCtx), MultiSelect.MultiSelectCount(module._msBossCtx))
        end,

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
            setPanelTitle(n, Helpers:BuildCountContextTitle(L.StrBosses, count, getSelectedRaidContextLabel(), nil))
            setFrameHint(n, "EmptyState", Helpers:BuildBossEmptyStateText(count, module.selectedRaid ~= nil))
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
    })

    Boss._ctrl = controller
    ListController.BindListController(Boss, controller)

    function Boss:Add()
        module.BossBox:Toggle()
    end

    function Boss:Edit()
        if module.selectedBoss then
            module.BossBox:Fill()
        end
    end

    do
        local function deleteBosses()
            module:Run(function(_, rID)
                local ctx = module._msBossCtx
                local ids = MultiSelect.MultiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then
                    return
                end

                for i = 1, #ids do
                    local bNid = ids[i]
                    local lootRemoved = Actions:DeleteBoss(rID, bNid)
                    addon:debug(Diag.D.LogLoggerBossLootRemoved, rID, tonumber(bNid) or -1, lootRemoved)
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
    controller = ListController.MakeListController({
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
                    module:SelectBossPlayer(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            local r, g, b = Colors.GetClassColor(it.class)
            ui.Name:SetText(it.name)
            ui.Name:SetVertexColor(r, g, b)
        end),

        highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module._msBossAttCtx, id)
        end,
        focusId = function()
            return module.selectedBossPlayer
        end,
        focusKey = function()
            return tostring(module.selectedBossPlayer or "nil")
        end,
        highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module._msBossAttCtx)
        end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msBossAttCtx), MultiSelect.MultiSelectCount(module._msBossAttCtx))
        end,

        postUpdate = function(n)
            local bSel = module.selectedBoss
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = MultiSelect.MultiSelectCount(module._msBossAttCtx)
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, Helpers:BuildCountContextTitle(L.StrBossAttendees, count, getSelectedBossContextLabel(), nil))
            setFrameHint(n, "EmptyState", Helpers:BuildBossAttendeesEmptyStateText(count, module.selectedRaid ~= nil, module.selectedBoss ~= nil))
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
    })

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
    controller = ListController.MakeListController({
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
            local raid = module:NeedRaid()
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
                    module:SelectPlayer(self, button)
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

        highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module._msRaidAttCtx, id)
        end,
        focusId = function()
            return module.selectedPlayer
        end,
        focusKey = function()
            return tostring(module.selectedPlayer or "nil")
        end,
        highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module._msRaidAttCtx)
        end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msRaidAttCtx), MultiSelect.MultiSelectCount(module._msRaidAttCtx))
        end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, Helpers:BuildCountContextTitle(L.StrRaidAttendees, count, getSelectedRaidContextLabel(), nil))
            setFrameHint(n, "EmptyState", Helpers:BuildRaidAttendeesEmptyStateText(count, module.selectedRaid ~= nil))
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
    })

    RaidAtt._ctrl = controller
    ListController.BindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function RaidAtt:Add()
        module:Run(function(_, rID)
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
    controller = ListController.MakeListController({
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

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

            -- Disabled until implemented
            _G[n .. "ExportBtn"]:Disable()
            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            local del = _G[n .. "DeleteBtn"]
            if del then
                del:SetText(L.BtnDelete)
            end
            _G[n .. "EditBtn"]:Disable()
            updateSourceHeaderState(n)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SafeSetScript(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                    Loot:Delete(self, button)
                end)
                Frames.SafeSetScript(_G[n .. "HeaderItem"], "OnClick", function()
                    Loot:Sort("id")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderSource"], "OnClick", function()
                    Loot:Sort("source")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderWinner"], "OnClick", function()
                    Loot:Sort("winner")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderType"], "OnClick", function()
                    Loot:Sort("type")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderRoll"], "OnClick", function()
                    Loot:Sort("roll")
                end)
                Frames.SafeSetScript(_G[n .. "HeaderTime"], "OnClick", function()
                    Loot:Sort("time")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = module:NeedRaid()
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
            if not row._krtBound then
                if row.RegisterForClicks then
                    row:RegisterForClicks("AnyUp")
                end
                Frames.SafeSetScript(row, "OnClick", function(self, button)
                    module:SelectItem(self, button)
                end)
                Frames.SafeSetScript(row, "OnEnter", function(self)
                    module:OnLootRowEnter(self)
                end)
                Frames.SafeSetScript(row, "OnLeave", function(self)
                    module:OnLootRowLeave(self)
                end)
                local itemButton = row.GetName and _G[row:GetName() .. "Item"] or nil
                Frames.SafeSetScript(itemButton, "OnEnter", function(self)
                    Loot:OnEnter(self)
                end)
                Frames.SafeSetScript(itemButton, "OnLeave", function()
                    GameTooltip:Hide()
                end)
                row._krtBound = true
            end
            local ui = row._p
            -- Preserve the original item link on the row for tooltips.
            row._itemLink = it.itemLink
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

            local winnerClass = it.looterClass or Services.Raid:GetPlayerClass(it.looter)
            local r, g, b = Colors.GetClassColor(winnerClass)
            ui.Winner:SetText(it.looter or "")
            ui.Winner:SetVertexColor(r, g, b)

            local rt = tonumber(it.rollType) or 0
            it.rollType = rt
            ui.Type:SetText(lootTypesColored[rt] or lootTypesColored[4])
            ui.Roll:SetText(it.rollValue or 0)
            ui.Time:SetText(it.timeFmt)

            local icon = it.itemTexture
            if not icon and it.itemId then
                icon = GetItemIcon(it.itemId)
            end
            if not icon then
                icon = C.RESERVES_ITEM_FALLBACK_ICON
            end
            ui.ItemIconTexture:SetTexture(icon)
        end),

        highlightFn = function(id)
            return MultiSelect.MultiSelectIsSelected(module._msLootCtx, id)
        end,
        focusId = function()
            return module.selectedItem
        end,
        focusKey = function()
            return tostring(module.selectedItem or "nil")
        end,
        highlightKey = function()
            return MultiSelect.MultiSelectGetVersion(module._msLootCtx)
        end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msLootCtx), MultiSelect.MultiSelectCount(module._msLootCtx))
        end,

        postUpdate = function(n)
            updateSourceHeaderState(n)

            local lootSelCount = MultiSelect.MultiSelectCount(module._msLootCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, lootSelCount)
            UIPrimitives.EnableDisable(delBtn, (lootSelCount or 0) > 0)
            setPanelTitle(n, Helpers:BuildCountContextTitle(L.StrRaidLoot, count, buildLootPanelContextLabel(), nil))
            setFrameHint(
                n,
                "EmptyState",
                Helpers:BuildLootEmptyStateText(count, module.selectedRaid ~= nil, (module.selectedBoss or module.selectedBossPlayer or module.selectedPlayer) ~= nil)
            )
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
    })

    Loot._ctrl = controller
    ListController.BindListController(Loot, controller)

    function Loot:Sort(key)
        if key == "source" and module.selectedBoss then
            return
        end
        controller:Sort(key)
    end

    function Loot:OnEnter(widget)
        if not widget then
            return
        end
        local row = (widget.IsObjectType and widget:IsObjectType("Button")) and widget or (widget.GetParent and widget:GetParent()) or widget
        if not (row and row.GetID) then
            return
        end

        local link = row._itemLink
        if not link then
            return
        end

        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
    end

    do
        local function deleteItem()
            module:Run(function(_, rID)
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

    local function findLootByItemId(raid, itemId)
        if not (raid and raid.loot) then
            return nil, 0
        end

        local queryItemId = tonumber(itemId)
        if not queryItemId then
            return nil, 0
        end

        local match = nil
        local matches = 0
        for i = #raid.loot, 1, -1 do
            local entry = raid.loot[i]
            if entry and tonumber(entry.itemId) == queryItemId then
                matches = matches + 1
                if not match then
                    match = entry
                end
            end
        end
        return match, matches
    end

    function Loot:Log(lootNid, looter, rollType, rollValue, source, raidIDOverride)
        local raidID
        if raidIDOverride then
            raidID = raidIDOverride
        else
            -- If the module window is open and browsing an old raid,
            -- selectedRaid may differ from Core.GetCurrentRaid().
            -- Runtime sources must always write into the CURRENT raid session.
            -- Logger UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = module.selectedRaid or Core.GetCurrentRaid()
            else
                raidID = Core.GetCurrentRaid() or module.selectedRaid
            end
        end
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
        local raid = raidID and Core.EnsureRaidById(raidID) or nil
        if not raid then
            addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(lootNid)))
            return false
        end

        Store:EnsureRaid(raid)
        local lootCount = raid.loot and #raid.loot or 0
        local it = Store:GetLoot(raid, lootNid)
        if not it then
            local rawItemMatch, rawItemMatches = findLootByItemId(raid, lootNid)
            if rawItemMatch and addon.error then
                addon:error(Diag.E.LogLoggerLootNidExpected:format(tostring(raidID), tostring(lootNid), tostring(rawItemMatch.itemLink), tonumber(rawItemMatches) or 0))
            end
            addon:error(Diag.E.LogLoggerItemNotFound:format(raidID, tostring(lootNid), lootCount))
            return false
        end

        if not looter or looter == "" then
            addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(Diag.W.LogLoggerRollTypeNil:format(raidID, tostring(lootNid), tostring(looter)))
        end

        local currentLooterName = Store:ResolveLootLooterName(raid, it)
        addon:debug(Diag.D.LogLoggerLootBefore:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(it.rollType), tostring(it.rollValue)))
        if currentLooterName and currentLooterName ~= "" and looter and looter ~= "" and currentLooterName ~= looter then
            addon:warn(Diag.W.LogLoggerLootOverwrite:format(raidID, tostring(lootNid), tostring(it.itemLink), tostring(currentLooterName), tostring(looter)))
        end

        local expectedLooterNid
        local expectedRollType
        local expectedRollValue
        if looter and looter ~= "" then
            local looterNid = Store:ResolveLootLooterNid(raid, looter)
            if not looterNid then
                addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(lootNid), tostring(it.itemLink)))
                return false
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

        controller:Dirty()
        local recordedLooterName = Store:ResolveLootLooterName(raid, it)
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

        addon:debug(Diag.D.LogLoggerVerified:format(raidID, tostring(lootNid)))
        if not Core.GetLastBoss() then
            addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(lootNid), tostring(it.itemLink)))
        end
        return true
    end

    Bus.RegisterCallback(InternalEvents.LoggerLootLogRequest, function(_, request)
        if type(request) ~= "table" then
            addon:error(Diag.E.LogLoggerLootLogRequestPayloadInvalid:format(type(request)))
            return
        end
        local raidId = request.raidId or request.raidID
        local lootNid = request.lootNid or request.itemID
        request.ok = Loot:Log(lootNid, request.looter, request.rollType, request.rollValue, request.source, raidId) == true
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

-- Add/edit boss popup (time/mode normalization).
do
    module.BossBox = module.BossBox or {}
    local Box = module.BossBox
    Box._ui = Box._ui or {
        Loaded = false,
        Bound = false,
        Localized = false,
        Dirty = true,
        Reason = nil,
        FrameName = nil,
    }
    local BoxUI = Box._ui
    local Store = module.Store

    local isEdit = false
    local tooltipsBound = false
    local raidData, bossData, tempDate = {}, {}, {}
    local editBossNid
    local getFrame = makeModuleFrameGetter(Box, "KRTLoggerBossBox")

    local function getBoxFrameName()
        return BoxUI.FrameName
    end

    local function getBoxPart(suffix)
        local frameName = getBoxFrameName()
        if not frameName then
            return nil
        end
        return _G[frameName .. suffix]
    end

    function Box.AcquireRefs(frame)
        return {
            title = Frames.Ref(frame, "Title"),
            name = Frames.Ref(frame, "Name"),
            difficulty = Frames.Ref(frame, "Difficulty"),
            time = Frames.Ref(frame, "Time"),
            nameStr = Frames.Ref(frame, "NameStr"),
            difficultyStr = Frames.Ref(frame, "DifficultyStr"),
            timeStr = Frames.Ref(frame, "TimeStr"),
            saveBtn = Frames.Ref(frame, "SaveBtn"),
            cancelBtn = Frames.Ref(frame, "CancelBtn"),
        }
    end

    local function bindBossBoxHandlers(_, frame, refs)
        if not frame or frame._krtBound then
            return
        end
        Frames.SafeSetScript(refs.saveBtn, "OnClick", function()
            Box:Save()
        end)
        Frames.SafeSetScript(refs.cancelBtn, "OnClick", function()
            Box:Hide()
        end)
        Frames.SafeSetScript(refs.name, "OnEnterPressed", function()
            Box:Save()
        end)
        Frames.SafeSetScript(refs.difficulty, "OnEnterPressed", function()
            Box:Save()
        end)
        Frames.SafeSetScript(refs.time, "OnEnterPressed", function()
            Box:Save()
        end)
        frame._krtBound = true
    end

    function Box:LocalizeUI(_, _, refs)
        if refs.nameStr then
            refs.nameStr:SetText(L.StrName)
        end
        if refs.difficultyStr then
            refs.difficultyStr:SetText(L.StrDifficulty)
        end
        if refs.timeStr then
            refs.timeStr:SetText(L.StrTime)
        end
        if refs.saveBtn then
            refs.saveBtn:SetText(L.BtnSave)
        end
        if refs.cancelBtn then
            refs.cancelBtn:SetText(L.BtnCancel)
        end
    end

    function Box:OnLoad(frame)
        BoxUI.FrameName = Frames.InitModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = function()
                Box:RequestRefresh("show")
            end,
            hookOnHide = function()
                Box:CancelAddEdit()
            end,
        }) or BoxUI.FrameName
        BoxUI.Loaded = BoxUI.FrameName ~= nil
        if not BoxUI.Loaded then
            return
        end
    end

    local function onLoadBossBoxFrame(frame)
        Box:OnLoad(frame)
        return BoxUI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = Box,
        getFrame = getFrame,
        acquireRefs = Box.AcquireRefs,
        bind = bindBossBoxHandlers,
        localize = function(frameName, frame, refs)
            Box:LocalizeUI(frameName, frame, refs)
        end,
        onLoad = onLoadBossBoxFrame,
        refresh = function()
            Box:RefreshUI()
        end,
    })

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
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

        local nameBox = getBoxPart("Name")
        local timeBox = getBoxPart("Time")
        local difficultyBox = getBoxPart("Difficulty")
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
        self:Toggle()
    end

    function Box:Save()
        local rID = module.selectedRaid
        if not rID then
            return
        end

        local nameBox = getBoxPart("Name")
        local difficultyBox = getBoxPart("Difficulty")
        local timeBox = getBoxPart("Time")
        if not (nameBox and difficultyBox and timeBox) then
            return
        end

        local name = Strings.TrimText(nameBox:GetText())
        local modeT = Strings.NormalizeLower(difficultyBox:GetText())
        local bTime = Strings.TrimText(timeBox:GetText())

        name = (name == "") and "_TrashMob_" or name
        if name ~= "_TrashMob_" and (modeT ~= "h" and modeT ~= "n") then
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

        self:Hide()
        module:ResetSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function Box:CancelAddEdit()
        Frames.ResetEditBox(getBoxPart("Name"))
        Frames.ResetEditBox(getBoxPart("Difficulty"))
        Frames.ResetEditBox(getBoxPart("Time"))
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    function Box:RefreshUI()
        local title = getBoxPart("Title")
        if not title then
            return
        end

        if not tooltipsBound then
            Frames.SetTooltip(getBoxPart("Name"), L.StrBossNameHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(getBoxPart("Difficulty"), L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(getBoxPart("Time"), L.StrBossTimeHelp, "ANCHOR_RIGHT")
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
    module.AttendeesBox = module.AttendeesBox or {}
    local Box = module.AttendeesBox
    Box._ui = Box._ui or {
        Loaded = false,
        Bound = false,
        Localized = false,
        Dirty = true,
        Reason = nil,
        FrameName = nil,
    }
    local BoxUI = Box._ui

    local getFrame = makeModuleFrameGetter(Box, "KRTLoggerPlayerBox")

    local function getBoxFrameName()
        return BoxUI.FrameName
    end

    local function getBoxPart(suffix)
        local frameName = getBoxFrameName()
        if not frameName then
            return nil
        end
        return _G[frameName .. suffix]
    end

    function Box.AcquireRefs(frame)
        return {
            title = Frames.Ref(frame, "Title"),
            nameStr = Frames.Ref(frame, "NameStr"),
            addBtn = Frames.Ref(frame, "AddBtn"),
            cancelBtn = Frames.Ref(frame, "CancelBtn"),
            name = Frames.Ref(frame, "Name"),
        }
    end

    local function bindAttendeesBoxHandlers(_, frame, refs)
        if not frame or frame._krtBound then
            return
        end
        Frames.SafeSetScript(refs.addBtn, "OnClick", function()
            Box:Save()
        end)
        Frames.SafeSetScript(refs.cancelBtn, "OnClick", function()
            Box:Hide()
        end)
        Frames.SafeSetScript(refs.name, "OnEnterPressed", function()
            Box:Save()
        end)
        frame._krtBound = true
    end

    function Box:LocalizeUI(_, _, refs)
        if refs.title then
            refs.title:SetText(L.StrAddPlayer)
        end
        if refs.nameStr then
            refs.nameStr:SetText(L.StrName)
        end
        if refs.addBtn then
            refs.addBtn:SetText(L.BtnAdd)
        end
        if refs.cancelBtn then
            refs.cancelBtn:SetText(L.BtnCancel)
        end
    end

    function Box:OnLoad(frame)
        BoxUI.FrameName = Frames.InitModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = function()
                Frames.ResetEditBox(getBoxPart("Name"))
            end,
            hookOnHide = function()
                Frames.ResetEditBox(getBoxPart("Name"))
            end,
        }) or BoxUI.FrameName
        BoxUI.Loaded = BoxUI.FrameName ~= nil
    end

    local function onLoadAttendeesBoxFrame(frame)
        Box:OnLoad(frame)
        return BoxUI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = Box,
        getFrame = getFrame,
        acquireRefs = Box.AcquireRefs,
        bind = bindAttendeesBoxHandlers,
        localize = function(frameName, frame, refs)
            Box:LocalizeUI(frameName, frame, refs)
        end,
        onLoad = onLoadAttendeesBoxFrame,
    })

    function Box:Save()
        local rID, bID = module.selectedRaid, module.selectedBoss
        local nameBox = getBoxPart("Name")
        if not nameBox then
            return
        end
        local name = Strings.TrimText(nameBox:GetText())
        if module.Actions:AddBossAttendee(rID, bID, name) then
            self:Toggle()
            triggerSelectionEvent(module, "selectedBoss")
        end
    end
end
