-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.getFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events or addon.Events or {}
local Bus = feature.Bus or addon.Bus

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

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
    addon.Changes = addon.Controllers.Changes -- Legacy alias during namespacing migration.
    local module = addon.Controllers.Changes
    local frameName

    local getFrame = makeModuleFrameGetter(module, "KRTChanges")
    -- ----- Internal state ----- --
    local LocalizeUIFrame
    local localized = false

    local UpdateUIFrame
    local changesTable = {}
    local tmpNames = {}
    local SaveChanges, CancelChanges
    local fetched = false
    local changesDirty = false
    local selectedID, tempSelectedID
    local lastSelectedID = false
    local lastEditBtnMode
    local lastAddBtnMode
    local isAdd = false
    local isEdit = false

    local controller = Utils.makeListController {
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

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.Name:SetText(it.name)
            local class = addon.Raid:GetPlayerClass(it.name)
            local r, g, b = Utils.getClassColor(class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Spec:SetText(it.spec or L.StrNone)
        end),

        highlightFn = function(_, it) return it and it.name == selectedID end,
        highlightKey = function() return tostring(selectedID or "nil") end,
    }

    local panelScaffold = UIScaffold.createListPanelScaffold({
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

    -- ----- Public methods ----- --

    -- OnLoad frame:
    function module:OnLoad(frame)
        frameName = panelScaffold:OnLoad(frame)
    end

    -- Clear module:
    function module:Clear()
        if not addon.Core.getCurrentRaid() or changesTable == nil then return end
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
        local name = _G[btnName .. "Name"]:GetText()
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
        if not addon.Core.getCurrentRaid() or not btn then return end
        if not selectedID then
            btn:Hide()
            _G[frameName .. "Name"]:Show()
            _G[frameName .. "Name"]:SetFocus()
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
        if not addon.Core.getCurrentRaid() then return end
        if not selectedID or isEdit then
            local name = _G[frameName .. "Name"]:GetText()
            local spec = _G[frameName .. "Spec"]:GetText()
            SaveChanges(name, spec)
        elseif changesTable[selectedID] then
            _G[frameName .. "Name"]:SetText(selectedID)
            _G[frameName .. "Spec"]:SetText(changesTable[selectedID])
            _G[frameName .. "Spec"]:Show()
            _G[frameName .. "Spec"]:SetFocus()
            isAdd = false
            isEdit = true
            module:RequestRefresh()
        end
    end

    -- Remove player's change:
    function module:Delete(name)
        if not addon.Core.getCurrentRaid() or not name then return end
        KRT_Raids[addon.Core.getCurrentRaid()].changes[name] = nil
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    Bus.registerCallback(InternalEvents.RaidLeave, function(e, name)
        module:Delete(name)
        CancelChanges()
    end)

    -- Ask For module:
    function module:Demand()
        if not addon.Core.getCurrentRaid() then return end
        addon:Announce(L.StrChangesDemand)
    end

    -- Spam module:
    function module:Announce()
        if not addon.Core.getCurrentRaid() then return end
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
        _G[frameName .. "ClearBtn"]:SetText(L.BtnClear)
        _G[frameName .. "AddBtn"]:SetText(L.BtnAdd)
        _G[frameName .. "EditBtn"]:SetText(L.BtnEdit)
        _G[frameName .. "DemandBtn"]:SetText(L.BtnDemand)
        _G[frameName .. "AnnounceBtn"]:SetText(L.BtnAnnounce)
        Utils.setFrameTitle(frameName, L.StrChanges)
        Utils.bindEditBoxHandlers(frameName, {
            { suffix = "Name", onEscape = CancelChanges, onEnter = module.Edit },
            { suffix = "Spec", onEscape = CancelChanges, onEnter = module.Edit },
        }, function()
            module:RequestRefresh()
        end)
        localized = true
    end

    -- UI refresh.
    function UpdateUIFrame()
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
        UIPrimitives.showHideNamedPart(frameName, "Name", (isEdit or isAdd))
        UIPrimitives.showHideNamedPart(frameName, "Spec", (isEdit or isAdd))
        UIPrimitives.enableDisableNamedPart(frameName, "EditBtn", (selectedID or isEdit or isAdd))
        local editBtnMode = isAdd or (selectedID and isEdit)
        lastEditBtnMode = UIPrimitives.updateModeTextNamedPart(
            frameName,
            "EditBtn",
            L.BtnSave,
            L.BtnEdit,
            editBtnMode,
            lastEditBtnMode
        )
        local addBtnMode = (not selectedID and not isEdit and not isAdd)
        lastAddBtnMode = UIPrimitives.updateModeTextNamedPart(
            frameName,
            "AddBtn",
            L.BtnAdd,
            L.BtnDelete,
            addBtnMode,
            lastAddBtnMode
        )
        UIPrimitives.showHideNamedPart(frameName, "AddBtn", (not isEdit and not isAdd))
        UIPrimitives.enableDisableNamedPart(frameName, "ClearBtn", count > 0)
        UIPrimitives.enableDisableNamedPart(frameName, "AnnounceBtn", count > 0)
        local hasRaid = addon.Core.getCurrentRaid()
        UIPrimitives.enableDisableNamedPart(frameName, "AddBtn", hasRaid)
        UIPrimitives.enableDisableNamedPart(frameName, "DemandBtn", hasRaid)
    end

    function module:Refresh()
        panelScaffold:Refresh()
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug(Diag.D.LogChangesInitTable)
        if not addon.Core.getCurrentRaid() then
            changesTable = {}
            return
        end
        local raid = KRT_Raids[addon.Core.getCurrentRaid()]
        raid.changes = raid.changes or {}
        changesTable = raid.changes
    end

    -- Save module:
    function SaveChanges(name, spec)
        if not addon.Core.getCurrentRaid() or not name then return end
        name = Utils.normalizeName(name)
        spec = Utils.normalizeName(spec)
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
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Spec"])
        module:RequestRefresh()
    end
end

