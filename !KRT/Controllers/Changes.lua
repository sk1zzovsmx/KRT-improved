-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local ListController = feature.ListController or addon.ListController
local Frames = feature.Frames or addon.Frames
local Colors = feature.Colors or addon.Colors
local Strings = feature.Strings or addon.Strings
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events or addon.Events or {}
local Bus = feature.Bus or addon.Bus
local Core = feature.Core or addon.Core

local bindModuleRequestRefresh = feature.BindModuleRequestRefresh
local bindModuleToggleHide = feature.BindModuleToggleHide
local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local twipe = table.wipe
local pairs, next = pairs, next
local format = string.format

local tostring = tostring

local InternalEvents = Events.Internal

-- =========== MS Changes Module  =========== --
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Changes = addon.Controllers.Changes or {}
    local module = addon.Controllers.Changes
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTChanges")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local changesTable = {}
    local tmpNames = {}
    local SaveChanges, CancelChanges, InitChangesTable
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false
    local uiBound = false
    local scaffoldToggle, scaffoldHide
    local AcquireRefs
    local BindChangeRow

    local controller = ListController.MakeListController {
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

        rowName = function(n, it) return n .. "PlayerBtn" .. it.id end,
        rowTmpl = "KRTChangesButtonTemplate",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            BindChangeRow(row)
            local ui = row._p
            ui.Name:SetText(it.name)
            local class = addon.Raid:GetPlayerClass(it.name)
            local r, g, b = Colors.GetClassColor(class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Spec:SetText(it.spec or L.StrNone)
        end),

        highlightFn = function(_, it) return it and it.name == selectedID end,
        highlightKey = function() return tostring(selectedID or "nil") end,
    }

    local panelScaffold = UIScaffold.CreateListPanelScaffold({
        module = module,
        getFrame = getFrame,
        controller = controller,
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
        onShow = function()
            changesDirty = true
            lastSelectedID = false
        end,
        onHide = function()
            if CancelChanges then
                CancelChanges()
            end
        end,
        localize = function()
            if LocalizeUIFrame then
                LocalizeUIFrame()
            end
        end,
        update = function()
            if UpdateUIFrame then
                UpdateUIFrame()
            end
        end,
    })

    -- ----- Private helpers ----- --
    function AcquireRefs(frame)
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

    function BindChangeRow(row)
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

    local function GetNamedPart(partName)
        local refs = module.refs
        local refKey = partToRefKey[partName]
        local ref = refs and refKey and refs[refKey] or nil
        if ref then
            return ref
        end
        if not frameName then
            return nil
        end
        return _G[frameName .. partName]
    end

    -- ----- Public methods ----- --
    scaffoldToggle = module.Toggle
    scaffoldHide = module.Hide

    function addon.Controllers.Changes:BindUI()
        if uiBound and self.frame and self.refs then
            return self.frame, self.refs
        end

        local frame = getFrame()
        if not frame then
            return nil
        end
        if not frameName then
            frameName = panelScaffold:OnLoad(frame) or frame:GetName()
        end

        local refs = AcquireRefs(frame)
        self.frame = frame
        self.refs = refs

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

        uiBound = true
        return frame, refs
    end

    function addon.Controllers.Changes:EnsureUI()
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

    -- OnLoad frame:
    function module:OnLoad(frame)
        frameName = panelScaffold:OnLoad(frame) or (frame and frame.GetName and frame:GetName() or frameName)
    end

    -- Clear module:
    function module:Clear()
        if not addon.Core.GetCurrentRaid() or changesTable == nil then return end
        for n in pairs(changesTable) do
            changesTable[n] = nil
        end
        CancelChanges()
        fetched = false
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    -- Selecting Player:
    function module:Select(btn)
        -- No selection.
        if not btn then return end
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
        if not name then return end
        -- Make sure the player exists in the raid:
        local found = true
        if not addon.Raid:CheckPlayer(name) then found = false end
        if not changesTable[name] then found = false end
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
        if not addon.Core.GetCurrentRaid() or not btn then return end
        if not selectedID then
            local nameBox = GetNamedPart("Name")
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
            changesTable[selectedID] = nil
            CancelChanges()
            fetched = false
            changesDirty = true
            controller:Dirty()
            module:RequestRefresh()
        end
    end

    -- Edit / Save
    function module:Edit()
        if not addon.Core.GetCurrentRaid() then return end
        local nameBox = GetNamedPart("Name")
        local specBox = GetNamedPart("Spec")
        if not (nameBox and specBox) then
            return
        end
        if not selectedID or isEdit then
            local name = nameBox:GetText()
            local spec = specBox:GetText()
            SaveChanges(name, spec)
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
        if not currentRaid or not name then return end
        local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
        local raid = raidStore and raidStore.GetRaidByIndex and raidStore:GetRaidByIndex(currentRaid) or nil
        if type(raid) ~= "table" or type(raid.changes) ~= "table" then
            return
        end
        raid.changes[name] = nil
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    Bus.RegisterCallback(InternalEvents.RaidLeave, function(e, name)
        module:Delete(name)
        CancelChanges()
    end)

    -- Ask For module:
    function module:Demand()
        if not addon.Core.GetCurrentRaid() then return end
        addon:Announce(L.StrChangesDemand)
    end

    -- Spam module:
    function module:Announce()
        if not addon.Core.GetCurrentRaid() then return end
        -- In case of a reload/relog and the frame wasn't loaded
        if not fetched or not next(changesTable) then
            InitChangesTable()
        end
        local count = addon.tLength(changesTable)
        local msg
        if count == 0 then
            if tempSelectedID then
                tempSelectedID = nil
                return
            end
            msg = L.StrChangesAnnounceNone
        elseif selectedID or tempSelectedID then
            local name = tempSelectedID and tempSelectedID or selectedID
            if tempSelectedID ~= nil then tempSelectedID = nil end
            if not changesTable[name] then return end
            msg = format(L.StrChangesAnnounceOne, name, changesTable[name])
        else
            msg = L.StrChangesAnnounce
            local names = tmpNames
            if twipe then
                twipe(names)
            else
                for i = 1, #names do
                    names[i] = nil
                end
            end
            for n in pairs(changesTable) do
                names[#names + 1] = n
            end
            table.sort(names)
            for i = 1, #names do
                local n = names[i]
                msg = msg .. " " .. n .. "=" .. tostring(changesTable[n])
                if i < #names then msg = msg .. " /" end
            end
        end
        addon:Announce(msg)
    end

    -- Localize UI Frame:
    function LocalizeUIFrame()
        if localized then return end
        if not frameName then
            return
        end
        local clearBtn = GetNamedPart("ClearBtn")
        if clearBtn then clearBtn:SetText(L.BtnClear) end
        local addBtn = GetNamedPart("AddBtn")
        if addBtn then addBtn:SetText(L.BtnAdd) end
        local editBtn = GetNamedPart("EditBtn")
        if editBtn then editBtn:SetText(L.BtnEdit) end
        local demandBtn = GetNamedPart("DemandBtn")
        if demandBtn then demandBtn:SetText(L.BtnDemand) end
        local announceBtn = GetNamedPart("AnnounceBtn")
        if announceBtn then announceBtn:SetText(L.BtnAnnounce) end
        Frames.SetFrameTitle(frameName, L.StrChanges)
        Frames.BindEditBoxHandlers(frameName, {
            { suffix = "Name", onEscape = CancelChanges, onEnter = module.Edit },
            { suffix = "Spec", onEscape = CancelChanges, onEnter = module.Edit },
        }, function()
            module:RequestRefresh()
        end)
        localized = true
    end

    -- UI refresh.
    function UpdateUIFrame()
        if not frameName then
            return
        end
        if changesDirty or not fetched then
            InitChangesTable()
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
        lastEditBtnMode = UIPrimitives.UpdateModeTextNamedPart(
            frameName,
            "EditBtn",
            L.BtnSave,
            L.BtnEdit,
            editBtnMode,
            lastEditBtnMode
        )
        local addBtnMode = (not selectedID and not isEdit and not isAdd)
        lastAddBtnMode = UIPrimitives.UpdateModeTextNamedPart(
            frameName,
            "AddBtn",
            L.BtnAdd,
            L.BtnDelete,
            addBtnMode,
            lastAddBtnMode
        )
        UIPrimitives.ShowHideNamedPart(frameName, "AddBtn", (not isEdit and not isAdd))
        UIPrimitives.EnableDisableNamedPart(frameName, "ClearBtn", count > 0)
        UIPrimitives.EnableDisableNamedPart(frameName, "AnnounceBtn", count > 0)
        local hasRaid = addon.Core.GetCurrentRaid()
        UIPrimitives.EnableDisableNamedPart(frameName, "AddBtn", hasRaid)
        UIPrimitives.EnableDisableNamedPart(frameName, "DemandBtn", hasRaid)
    end

    function module:Refresh()
        panelScaffold:Refresh()
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug(Diag.D.LogChangesInitTable)
        local currentRaid = Core.GetCurrentRaid()
        if not currentRaid then
            changesTable = {}
            return
        end
        local raidStore = Core.GetRaidStore and Core.GetRaidStore() or nil
        local raid = raidStore and raidStore.GetRaidByIndex and raidStore:GetRaidByIndex(currentRaid) or nil
        if type(raid) ~= "table" then
            changesTable = {}
            return
        end
        raid.changes = raid.changes or {}
        changesTable = raid.changes
    end

    -- Save module:
    function SaveChanges(name, spec)
        if not addon.Core.GetCurrentRaid() or not name then return end
        name = Strings.NormalizeName(name)
        spec = Strings.NormalizeName(spec)
        -- Is the player in the raid?
        local found
        found, name = addon.Raid:CheckPlayer(name)
        if not found then
            addon:error(format((name == "" and L.ErrChangesNoPlayer or L.ErrCannotFindPlayer), name))
            return
        end
        changesTable[name] = (spec == "") and nil or spec
        CancelChanges()
        fetched = false
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    -- Cancel all actions:
    function CancelChanges()
        isAdd = false
        isEdit = false
        selectedID = nil
        tempSelectedID = nil
        local nameBox = GetNamedPart("Name")
        if nameBox then
            Frames.ResetEditBox(nameBox)
        end
        local specBox = GetNamedPart("Spec")
        if specBox then
            Frames.ResetEditBox(specBox)
        end
        module:RequestRefresh()
    end
end

