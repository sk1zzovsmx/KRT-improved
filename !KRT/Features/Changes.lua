--[[
    Features/Changes.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local _G = _G
local twipe = table.wipe
local pairs, next = pairs, next
local format = string.format

local tostring = tostring

-- =========== MS Changes Module  =========== --
do
    addon.Changes = addon.Changes or {}
    local module = addon.Changes
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

    -- ----- Private helpers ----- --

    -- ----- Public methods ----- --

    -- OnLoad frame:
    function module:OnLoad(frame)
        frameName = Utils.initModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                changesDirty = true
                lastSelectedID = false
            end,
            hookOnHide = function()
                CancelChanges()
            end,
        })
        if not frameName then return end
        controller:OnLoad(frame)
    end

    -- Initialize UI controller for Toggle/Hide.
    Utils.bootstrapModuleUi(module, getFrame, function()
        changesDirty = true
        lastSelectedID = false
        module:RequestRefresh()
    end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    -- Clear module:
    function module:Clear()
        if not addon.State.currentRaid or changesTable == nil then return end
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
        if not addon.State.currentRaid or not btn then return end
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
        if not addon.State.currentRaid then return end
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
        if not addon.State.currentRaid or not name then return end
        KRT_Raids[addon.State.currentRaid].changes[name] = nil
        changesDirty = true
        controller:Dirty()
        module:RequestRefresh()
    end

    Utils.registerCallback("RaidLeave", function(e, name)
        module:Delete(name)
        CancelChanges()
    end)

    -- Ask For module:
    function module:Demand()
        if not addon.State.currentRaid then return end
        addon:Announce(L.StrChangesDemand)
    end

    -- Spam module:
    function module:Announce()
        if not addon.State.currentRaid then return end
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
        _G[frameName .. "Name"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Spec"]:SetScript("OnEnterPressed", module.Edit)
        _G[frameName .. "Name"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Spec"]:SetScript("OnEscapePressed", CancelChanges)
        _G[frameName .. "Name"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        _G[frameName .. "Spec"]:SetScript("OnTextChanged", function(_, isUserInput)
            if isUserInput then
                module:RequestRefresh()
            end
        end)
        localized = true
    end

    -- UI refresh.
    function UpdateUIFrame()
        LocalizeUIFrame()
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
        Utils.showHide(_G[frameName .. "Name"], (isEdit or isAdd))
        Utils.showHide(_G[frameName .. "Spec"], (isEdit or isAdd))
        Utils.enableDisable(_G[frameName .. "EditBtn"], (selectedID or isEdit or isAdd))
        local editBtnMode = isAdd or (selectedID and isEdit)
        if editBtnMode ~= lastEditBtnMode then
            Utils.setText(_G[frameName .. "EditBtn"], L.BtnSave, L.BtnEdit, editBtnMode)
            lastEditBtnMode = editBtnMode
        end
        local addBtnMode = (not selectedID and not isEdit and not isAdd)
        if addBtnMode ~= lastAddBtnMode then
            Utils.setText(_G[frameName .. "AddBtn"], L.BtnAdd, L.BtnDelete, addBtnMode)
            lastAddBtnMode = addBtnMode
        end
        Utils.showHide(_G[frameName .. "AddBtn"], (not isEdit and not isAdd))
        Utils.enableDisable(_G[frameName .. "ClearBtn"], count > 0)
        Utils.enableDisable(_G[frameName .. "AnnounceBtn"], count > 0)
        Utils.enableDisable(_G[frameName .. "AddBtn"], addon.State.currentRaid)
        Utils.enableDisable(_G[frameName .. "DemandBtn"], addon.State.currentRaid)
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
    end

    -- Initialize changes table:
    function InitChangesTable()
        addon:debug(Diag.D.LogChangesInitTable)
        if not addon.State.currentRaid then
            changesTable = {}
            return
        end
        local raid = KRT_Raids[addon.State.currentRaid]
        raid.changes = raid.changes or {}
        changesTable = raid.changes
    end

    -- Save module:
    function SaveChanges(name, spec)
        if not addon.State.currentRaid or not name then return end
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
