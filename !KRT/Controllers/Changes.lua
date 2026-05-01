-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local ListController = feature.ListController
local Frames = feature.Frames
local Colors = feature.Colors
local Strings = feature.Strings
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events
local Bus = feature.Bus
local Core = feature.Core
local Services = feature.Services

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local twipe = table.wipe
local pairs, next = pairs, next
local format = string.format

local tostring = tostring

local InternalEvents = Events.Internal

local requireServiceMethod = Core.RequireServiceMethod

local Raid = Services.Raid
local Chat = Services.Chat
local RaidApi = {
    GetPlayerClass = requireServiceMethod("Raid", Raid, "GetPlayerClass"),
    CheckPlayer = requireServiceMethod("Raid", Raid, "CheckPlayer"),
    ClearRaidChanges = requireServiceMethod("Raid", Raid, "ClearRaidChanges"),
    DeleteRaidChange = requireServiceMethod("Raid", Raid, "DeleteRaidChange"),
    CanBroadcastChanges = requireServiceMethod("Raid", Raid, "CanBroadcastChanges"),
    BuildRaidChangesDemandText = requireServiceMethod("Raid", Raid, "BuildRaidChangesDemandText"),
    BuildRaidChangesAnnouncement = requireServiceMethod("Raid", Raid, "BuildRaidChangesAnnouncement"),
    GetRaidChanges = requireServiceMethod("Raid", Raid, "GetRaidChanges"),
    UpsertRaidChange = requireServiceMethod("Raid", Raid, "UpsertRaidChange"),
}
local ChatApi = {
    Announce = requireServiceMethod("Chat", Chat, "Announce"),
}

-- =========== MS Changes Module  =========== --
do
    addon.Controllers.Changes = addon.Controllers.Changes or {}
    local module = addon.Controllers.Changes
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui

    local getFrame = makeModuleFrameGetter(module, "KRTChanges")
    -- ----- Internal state ----- --

    local changesTable = {}
    local tmpNames = {}
    local saveChanges, cancelChanges, initChangesTable
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false
    local bindChangeRow
    local controller

    local function isDebugEnabled()
        return addon.hasDebug ~= nil
    end

    local function markChangesDirty()
        fetched = false
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    local function notifyChangesUpdated(raidId, reason, playerName)
        if not (Bus and Bus.TriggerEvent and InternalEvents.RaidChangesUpdated) then
            return
        end
        Bus.TriggerEvent(InternalEvents.RaidChangesUpdated, raidId, reason, playerName)
    end

    controller = ListController.MakeListController({
        keyName = "ChangesList",
        poolTag = "changes",
        _rowParts = { "Name", "Spec" },

        getData = function(out)
            local names = tmpNames
            if twipe then
                twipe(names)
            else
                for i = 1, #names do
                    names[i] = nil
                end
            end
            for name in pairs(changesTable) do
                names[#names + 1] = name
            end
            table.sort(names)
            for i = 1, #names do
                local name = names[i]
                out[i] = { id = i, name = name, spec = changesTable[name] }
            end
        end,

        rowName = function(n, it)
            return n .. "PlayerBtn" .. it.id
        end,
        rowTmpl = "KRTChangesButtonTemplate",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            bindChangeRow(row)
            local ui = row._p
            ui.Name:SetText(it.name)
            local class = RaidApi.GetPlayerClass(Raid, it.name)
            local r, g, b = Colors.GetClassColor(class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Spec:SetText(it.spec or L.StrNone)
        end),

        highlightFn = function(_, it)
            return it and it.name == selectedID
        end,
        highlightKey = function()
            return tostring(selectedID or "nil")
        end,
    })

    local panelScaffold = UIScaffold.CreateListPanelScaffold({
        module = module,
        getFrame = getFrame,
        controller = controller,
        onShow = function()
            changesDirty = true
            lastSelectedID = false
        end,
        onHide = function()
            if cancelChanges then
                cancelChanges()
            end
        end,
        localize = function()
            UI.Localize()
        end,
        update = function()
            UI.Refresh()
        end,
    })

    -- ----- Private helpers ----- --
    function UI.AcquireRefs(frame)
        return {
            addBtn = Frames.Ref(frame, "AddBtn"),
            announceBtn = Frames.Ref(frame, "AnnounceBtn"),
            clearBtn = Frames.Ref(frame, "ClearBtn"),
            demandBtn = Frames.Ref(frame, "DemandBtn"),
            editBtn = Frames.Ref(frame, "EditBtn"),
            name = Frames.Ref(frame, "Name"),
            spec = Frames.Ref(frame, "Spec"),
        }
    end

    function bindChangeRow(row)
        if not row or row._krtBound then
            return
        end
        Frames.SafeSetScript(row, "OnClick", function(self, button)
            module:Select(self, button)
        end)
        Frames.SafeSetScript(row, "OnDoubleClick", function(self)
            module:Edit(self)
        end)
        row._krtBound = true
    end

    local partToRefKey = {
        AddBtn = "addBtn",
        AnnounceBtn = "announceBtn",
        ClearBtn = "clearBtn",
        DemandBtn = "demandBtn",
        EditBtn = "editBtn",
        Name = "name",
        Spec = "spec",
    }

    local function getNamedPart(partName)
        local refs = module.refs
        local refKey = partToRefKey[partName]
        local ref = refs and refKey and refs[refKey] or nil
        if ref then
            return ref
        end
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
        return _G[frameName .. partName]
    end

    local function BindHandlers(_, _, refs)
        Frames.SafeSetScript(refs.addBtn, "OnClick", function(self, button)
            module:Add(self, button)
        end)
        Frames.SafeSetScript(refs.announceBtn, "OnClick", function()
            module:Announce()
        end)
        Frames.SafeSetScript(refs.clearBtn, "OnClick", function()
            module:Clear()
        end)
        Frames.SafeSetScript(refs.demandBtn, "OnClick", function()
            module:Demand()
        end)
        Frames.SafeSetScript(refs.editBtn, "OnClick", function(self, button)
            module:Edit(self, button)
        end)
        Frames.SafeSetScript(refs.name, "OnTabPressed", function(self)
            local spec = Frames.Ref(self:GetParent(), "Spec")
            if spec and spec.SetFocus then
                spec:SetFocus()
            end
        end)
        Frames.SafeSetScript(refs.spec, "OnTabPressed", function(self)
            local name = Frames.Ref(self:GetParent(), "Name")
            if name and name.SetFocus then
                name:SetFocus()
            end
        end)
    end

    local function OnLoadFrame(frame)
        UI.FrameName = panelScaffold:OnLoad(frame) or (frame and frame.GetName and frame:GetName() or UI.FrameName)
        UI.Loaded = UI.FrameName ~= nil
        return UI.FrameName
    end

    -- ----- Public methods ----- --
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

    -- OnLoad frame:
    function module:OnLoad(frame)
        return OnLoadFrame(frame)
    end

    -- Clear module:
    function module:Clear()
        local currentRaid = Core.GetCurrentRaid()
        if not currentRaid then
            return
        end

        local ok = RaidApi.ClearRaidChanges(Raid, currentRaid)
        if not ok then
            return
        end

        notifyChangesUpdated(currentRaid, "clear")
        cancelChanges()
        markChangesDirty()
    end

    -- Selecting Player:
    function module:Select(btn)
        -- No selection.
        if not btn then
            return
        end
        local btnName = btn:GetName()
        if not btnName or btnName == "" then
            return
        end
        local nameLabel = _G[btnName .. "Name"]
        if not (nameLabel and nameLabel.GetText) then
            return
        end
        local name = nameLabel:GetText()
        -- No ID set.
        if not name then
            return
        end
        -- Make sure the player exists in the raid:
        local found = true
        if not RaidApi.CheckPlayer(Raid, name) then
            found = false
        end
        if not changesTable[name] then
            found = false
        end
        if not found then
            fetched = false
            changesDirty = true
            controller:Dirty()
            module:RequestRefresh()
            return
        end
        -- Quick announce?
        if IsControlKeyDown() then
            tempSelectedID = (name ~= selectedID) and name or nil
            self:Announce()
            return
        end
        -- Selection:
        selectedID = (name ~= selectedID) and name or nil
        isAdd = false
        isEdit = false
        module:RequestRefresh()
    end

    -- Add / Delete:
    function module:Add(btn)
        if not addon.Core.GetCurrentRaid() or not btn then
            return
        end
        if not selectedID then
            local nameBox = getNamedPart("Name")
            if not nameBox then
                return
            end
            btn:Hide()
            nameBox:Show()
            if nameBox.SetFocus then
                nameBox:SetFocus()
            end
            isAdd = true
            module:RequestRefresh()
        elseif changesTable[selectedID] then
            local currentRaid = Core.GetCurrentRaid()
            if not currentRaid then
                return
            end
            local ok = RaidApi.DeleteRaidChange(Raid, currentRaid, selectedID)
            if not ok then
                return
            end
            notifyChangesUpdated(currentRaid, "delete", selectedID)
            cancelChanges()
            markChangesDirty()
        end
    end

    -- Edit / Save
    function module:Edit()
        if not addon.Core.GetCurrentRaid() then
            return
        end
        local nameBox = getNamedPart("Name")
        local specBox = getNamedPart("Spec")
        if not (nameBox and specBox) then
            return
        end
        if not selectedID or isEdit then
            local name = nameBox:GetText()
            local spec = specBox:GetText()
            saveChanges(name, spec)
        elseif changesTable[selectedID] then
            nameBox:SetText(selectedID)
            specBox:SetText(changesTable[selectedID])
            specBox:Show()
            if specBox.SetFocus then
                specBox:SetFocus()
            end
            isAdd = false
            isEdit = true
            module:RequestRefresh()
        end
    end

    -- Remove player's change:
    function module:Delete(name)
        local currentRaid = Core.GetCurrentRaid()
        if not currentRaid or not name then
            return
        end
        local ok = RaidApi.DeleteRaidChange(Raid, currentRaid, name)
        if not ok then
            return
        end
        notifyChangesUpdated(currentRaid, "delete", name)
        markChangesDirty()
    end

    Bus.RegisterCallback(InternalEvents.RaidLeave, function(_, name)
        module:Delete(name)
        cancelChanges()
    end)

    Bus.RegisterCallback(InternalEvents.RaidChangesUpdated, function(_, raidId)
        if tostring(raidId or "") ~= tostring(Core.GetCurrentRaid() or "") then
            return
        end
        markChangesDirty()
    end)

    local function canBroadcastChanges()
        return RaidApi.CanBroadcastChanges(Raid)
    end

    local function warnBroadcastDenied(reason)
        if reason == "missing_leadership" or reason == "missing_rank" then
            addon:warn(L.WarnChangesBroadcastNotAllowed)
        end
    end

    function module:CanBroadcast()
        return canBroadcastChanges()
    end

    -- Ask For module:
    function module:Demand()
        local ok, reason = canBroadcastChanges()
        if not ok then
            warnBroadcastDenied(reason)
            return
        end

        local msg = RaidApi.BuildRaidChangesDemandText(Raid)
        ChatApi.Announce(Chat, msg)
    end

    -- Spam module:
    function module:Announce()
        local ok, reason = canBroadcastChanges()
        if not ok then
            warnBroadcastDenied(reason)
            return
        end
        -- In case of a reload/relog and the frame wasn't loaded
        if not fetched or not next(changesTable) then
            initChangesTable()
        end

        local selectedName = tempSelectedID and tempSelectedID or selectedID
        local hadTempSelected = tempSelectedID ~= nil
        if tempSelectedID ~= nil then
            tempSelectedID = nil
        end

        local msg, count = RaidApi.BuildRaidChangesAnnouncement(Raid, changesTable, selectedName, tmpNames)

        if hadTempSelected and (tonumber(count) or 0) == 0 then
            return
        end
        if not msg then
            return
        end
        ChatApi.Announce(Chat, msg)
    end

    -- Localize UI Frame:
    function UI.Localize()
        if UI.Localized then
            return
        end
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        local clearBtn = getNamedPart("ClearBtn")
        if clearBtn then
            clearBtn:SetText(L.BtnClear)
        end
        local addBtn = getNamedPart("AddBtn")
        if addBtn then
            addBtn:SetText(L.BtnAdd)
        end
        local editBtn = getNamedPart("EditBtn")
        if editBtn then
            editBtn:SetText(L.BtnEdit)
        end
        local demandBtn = getNamedPart("DemandBtn")
        if demandBtn then
            demandBtn:SetText(L.BtnDemand)
        end
        local announceBtn = getNamedPart("AnnounceBtn")
        if announceBtn then
            announceBtn:SetText(L.BtnAnnounce)
        end
        Frames.SetFrameTitle(frameName, L.StrChanges)
        Frames.BindEditBoxHandlers(frameName, {
            { suffix = "Name", onEscape = cancelChanges, onEnter = module.Edit },
            { suffix = "Spec", onEscape = cancelChanges, onEnter = module.Edit },
        }, function()
            module:RequestRefresh()
        end)
        UI.Localized = true
    end

    -- UI refresh.
    function UI.Refresh()
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        if changesDirty or not fetched then
            initChangesTable()
            controller:Dirty()
            changesDirty = false
            fetched = true
        end
        local count = addon.tLength(changesTable)
        if count <= 0 then
            tempSelectedID = nil
            selectedID = nil
        end
        if selectedID ~= lastSelectedID then
            lastSelectedID = selectedID
            controller:Touch()
        end
        UIPrimitives.ShowHideNamedPart(frameName, "Name", (isEdit or isAdd))
        UIPrimitives.ShowHideNamedPart(frameName, "Spec", (isEdit or isAdd))
        UIPrimitives.EnableDisableNamedPart(frameName, "EditBtn", (selectedID or isEdit or isAdd))
        local editBtnMode = isAdd or (selectedID and isEdit)
        lastEditBtnMode = UIPrimitives.UpdateModeTextNamedPart(frameName, "EditBtn", L.BtnSave, L.BtnEdit, editBtnMode, lastEditBtnMode)
        local addBtnMode = (not selectedID and not isEdit and not isAdd)
        lastAddBtnMode = UIPrimitives.UpdateModeTextNamedPart(frameName, "AddBtn", L.BtnAdd, L.BtnDelete, addBtnMode, lastAddBtnMode)
        UIPrimitives.ShowHideNamedPart(frameName, "AddBtn", (not isEdit and not isAdd))
        UIPrimitives.EnableDisableNamedPart(frameName, "ClearBtn", count > 0)
        local canBroadcast = module:CanBroadcast()
        UIPrimitives.EnableDisableNamedPart(frameName, "AnnounceBtn", count > 0 and canBroadcast)
        local hasRaid = addon.Core.GetCurrentRaid()
        UIPrimitives.EnableDisableNamedPart(frameName, "AddBtn", hasRaid)
        UIPrimitives.EnableDisableNamedPart(frameName, "DemandBtn", canBroadcast)
    end

    function module:RefreshUI()
        panelScaffold:Refresh()
    end

    function module:Refresh()
        return self:RefreshUI()
    end

    -- Initialize changes table:
    function initChangesTable()
        if isDebugEnabled() then
            addon:debug(Diag.D.LogChangesInitTable)
        end
        local currentRaid = Core.GetCurrentRaid()
        if not currentRaid then
            changesTable = {}
            return
        end

        local changes = RaidApi.GetRaidChanges(Raid, currentRaid)
        if type(changes) ~= "table" then
            changesTable = {}
            return
        end
        changesTable = changes
    end

    -- Save module:
    function saveChanges(name, spec)
        local currentRaid = Core.GetCurrentRaid()
        if not currentRaid or not name then
            return
        end
        name = Strings.NormalizeName(name)
        spec = Strings.NormalizeName(spec)
        -- Is the player in the raid?
        local found
        found, name = RaidApi.CheckPlayer(Raid, name)
        if not found then
            addon:error(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
            return
        end

        local ok, savedName = RaidApi.UpsertRaidChange(Raid, currentRaid, name, spec)
        if not ok then
            return
        end

        local reason = (spec == nil or spec == "") and "delete" or "save"
        notifyChangesUpdated(currentRaid, reason, savedName)
        cancelChanges()
        markChangesDirty()
    end

    -- Cancel all actions:
    function cancelChanges()
        isAdd = false
        isEdit = false
        selectedID = nil
        tempSelectedID = nil
        local nameBox = getNamedPart("Name")
        if nameBox then
            Frames.ResetEditBox(nameBox)
        end
        local specBox = getNamedPart("Spec")
        if specBox then
            Frames.ResetEditBox(specBox)
        end
        module:RequestRefresh()
    end
end
