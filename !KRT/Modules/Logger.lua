local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper
local rollTypes = C.rollTypes
local lootTypesColored = C.lootTypesColored
local itemColors = C.itemColors

-- Logger Frame
-- Shown loot logger for raids
-- ============================================================================
do
    addon.Logger = addon.Logger or {}
    local Logger = addon.Logger
    local L = addon.L

    local frameName

    Logger.selectedRaid = nil
    Logger.selectedBoss = nil
    Logger.selectedPlayer = nil
    Logger.selectedBossPlayer = nil
    Logger.selectedItem = nil

    local function clearSelections()
        Logger.selectedBoss = nil
        Logger.selectedPlayer = nil
        Logger.selectedBossPlayer = nil
        Logger.selectedItem = nil
    end

    local function toggleSelection(field, id, eventName)
        Logger[field] = (id and id ~= Logger[field]) and id or nil
        if eventName then
            Utils.triggerEvent(eventName, Logger[field])
        end
    end

    function Logger:ResetSelections()
        clearSelections()
    end

    function Logger:OnLoad(frame)
        UILogger, frameName = frame, frame:GetName()
        frame:RegisterForDrag("LeftButton")
        Utils.setFrameTitle(frameName, L.StrLootLogger)

        frame:SetScript("OnShow", function()
            if not Logger.selectedRaid then
                Logger.selectedRaid = KRT_CurrentRaid
            end
            clearSelections()
            Utils.triggerEvent("LoggerSelectRaid", Logger.selectedRaid)
        end)

        frame:SetScript("OnHide", function()
            Logger.selectedRaid = KRT_CurrentRaid
            clearSelections()
        end)
    end

    function Logger:Toggle() Utils.toggle(UILogger) end

    function Logger:Hide()
        Logger.selectedRaid = KRT_CurrentRaid
        clearSelections()
        Utils.showHide(UILogger, false)
    end

    -- Selectors
    function Logger:SelectRaid(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedRaid = (id and id ~= Logger.selectedRaid) and id or nil
        clearSelections()
        Utils.triggerEvent("LoggerSelectRaid", Logger.selectedRaid)
    end

    function Logger:SelectBoss(btn)
        local id = btn and btn.GetID and btn:GetID()
        toggleSelection("selectedBoss", id, "LoggerSelectBoss")
    end

    -- Player filter: only one active at a time
    function Logger:SelectBossPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedPlayer = nil
        toggleSelection("selectedBossPlayer", id, "LoggerSelectBossPlayer")
        Utils.triggerEvent("LoggerSelectPlayer", Logger.selectedPlayer)
    end

    function Logger:SelectPlayer(btn)
        local id = btn and btn.GetID and btn:GetID()
        Logger.selectedBossPlayer = nil
        toggleSelection("selectedPlayer", id, "LoggerSelectPlayer")
        Utils.triggerEvent("LoggerSelectBossPlayer", Logger.selectedBossPlayer)
    end

    -- Item: left select, right menu
    do
        local function openItemMenu()
            local f = _G.KRTLoggerItemMenuFrame
                or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")

            EasyMenu({
                { text = L.StrEditItemLooter,    func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER") end },
                { text = L.StrEditItemRollType,  func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_ROLL") end },
                { text = L.StrEditItemRollValue, func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE") end },
            }, f, "cursor", 0, 0, "MENU")
        end

        function Logger:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            if button == "LeftButton" then
                toggleSelection("selectedItem", id, "LoggerSelectItem")
            elseif button == "RightButton" then
                Logger.selectedItem = id
                Utils.triggerEvent("LoggerSelectItem", Logger.selectedItem)
                openItemMenu()
            end
        end

        local function findLoggerPlayer(normalizedName, raid, bossKill)
            if raid and raid.players then
                for _, p in ipairs(raid.players) do
                    if normalizedName == Utils.normalizeLower(p.name) then
                        return p.name
                    end
                end
            end
            if bossKill and bossKill.players then
                for _, name in ipairs(bossKill.players) do
                    if normalizedName == Utils.normalizeLower(name) then
                        return name
                    end
                end
            end
        end

        local function isValidRollType(rollType)
            for _, value in pairs(rollTypes) do
                if rollType == value then
                    return true
                end
            end
            return false
        end

        local function validateRollType(_, text)
            local value = text and tonumber(text)
            if not value or not isValidRollType(value) then
                addon:error(L.ErrLoggerInvalidRollType)
                return false
            end
            return true, value
        end

        local function validateRollValue(_, text)
            local value = text and tonumber(text)
            if not value or value < 0 then
                addon:error(L.ErrLoggerInvalidRollValue)
                return false
            end
            return true, value
        end

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp,
            function(self, text)
                local rawText = Utils.trimText(text)
                local name = Utils.normalizeLower(rawText)
                if not name or name == "" then
                    addon:error(L.ErrLoggerWinnerEmpty)
                    return
                end

                local raid = KRT_Raids[self.raidId]
                if not raid then
                    addon:error(L.ErrLoggerInvalidRaid)
                    return
                end

                local loot = raid.loot and raid.loot[self.itemId]
                if not loot then
                    addon:error(L.ErrLoggerInvalidItem)
                    return
                end

                local bossKill = raid.bossKills and raid.bossKills[loot.bossNum]
                local winner = findLoggerPlayer(name, raid, bossKill)
                if not winner then
                    addon:error(L.ErrLoggerWinnerNotFound:format(rawText))
                    return
                end

                addon.Logger.Loot:Log(self.itemId, winner, nil, nil, "LOGGER_EDIT_WINNER")
            end,
            function(self)
                self.raidId = addon.Logger.selectedRaid
                self.itemId = addon.Logger.selectedItem
            end
        )

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_ROLL", L.StrEditItemRollTypeHelp,
            function(self, text)
                addon.Logger.Loot:Log(self.itemId, nil, text, nil, "LOGGER_EDIT_ROLLTYPE")
            end,
            function(self) self.itemId = addon.Logger.selectedItem end,
            validateRollType
        )

        Utils.makeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp,
            function(self, text)
                addon.Logger.Loot:Log(self.itemId, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
            end,
            function(self) self.itemId = addon.Logger.selectedItem end,
            validateRollValue
        )
    end
end

-- ============================================================================
-- Logger list controller helpers (Logger-only)
-- ============================================================================
local makeLoggerListController
local bindLoggerListController

do
    local CreateFrame = CreateFrame
    local math_max = math.max

    function makeLoggerListController(cfg)
        local self = {
            frameName = nil,
            data = {},
            _rows = {},
            _rowByName = {},
            _asc = false,
            _lastHL = nil,
            _active = false,
            _localized = false,
            _lastWidth = nil,
            _dirty = true,
        }

        local defer = CreateFrame("Frame")
        defer:Hide()

        local function buildRowParts(btnName, row)
            if cfg._rowParts and not row._p then
                local p = {}
                for i = 1, #cfg._rowParts do
                    local part = cfg._rowParts[i]
                    p[part] = _G[btnName .. part]
                end
                row._p = p
            end
        end

        local function acquireRow(btnName, parent)
            local row = self._rowByName[btnName]
            if row then
                row:Show()
                return row
            end

            row = CreateFrame("Button", btnName, parent, cfg.rowTmpl)
            self._rowByName[btnName] = row
            buildRowParts(btnName, row)
            return row
        end

        local function releaseData()
            for i = 1, #self.data do
                twipe(self.data[i])
            end
            twipe(self.data)
        end

        local function refreshData()
            releaseData()
            if cfg.getData then
                cfg.getData(self.data)
            end
        end

        local function ensureLocalized()
            if not self._localized and cfg.localize then
                cfg.localize(self.frameName)
                self._localized = true
            end
        end

        local function setActive(active)
            self._active = active
            if self._active then
                ensureLocalized()
                -- Reset one-shot diagnostics each time the list becomes active (OnShow).
                self._loggedFetch = nil
                self._loggedWidgets = nil
                self._warnW0 = nil
                self._missingScroll = nil
                self:Dirty()
                return
            end
            releaseData()
            for i = 1, #self._rows do
                local row = self._rows[i]
                if row then row:Hide() end
            end
            self._lastHL = nil
        end

        local function applyHighlight()
            if not cfg.highlightId then return end
            local sel = cfg.highlightId()
            if sel == self._lastHL then return end
            self._lastHL = sel
            for i = 1, #self.data do
                local it = self.data[i]
                local row = self._rows[i]
                if row then
                    Utils.toggleHighlight(row, sel ~= nil and it.id == sel)
                end
            end
        end

        local function postUpdate()
            if cfg.postUpdate then
                cfg.postUpdate(self.frameName)
            end
        end

        function self:Touch()
            defer:Show()
        end

        function self:Dirty()
            self._dirty = true
            defer:Show()
        end

        local function runUpdate()
            if not self._active or not self.frameName then return end

            if self._dirty then
                refreshData()
                local okFetch = self:Fetch()
                -- If Fetch() returns false we defer until the frame has a real size.
                if okFetch ~= false then
                    self._dirty = false
                end
            end

            applyHighlight()
            postUpdate()
        end

        defer:SetScript("OnUpdate", function(f)
            f:Hide()
            local ok, err = pcall(runUpdate)
            if not ok then
                -- If the user has script errors disabled, this still surfaces the problem in chat.
                if err ~= self._lastErr then
                    self._lastErr = err
                    addon:error(L.LogLoggerUIError:format(tostring(cfg.keyName or "?"), tostring(err)))
                end
            end
        end)

        function self:OnLoad(frame)
            if not frame then return end
            self.frameName = frame:GetName()

            frame:SetScript("OnShow", function()
                if not self._shownOnce then
                    self._shownOnce = true
                    addon:debug(L.LogLoggerUIShow:format(tostring(cfg.keyName or "?"), tostring(self.frameName)))
                end
                setActive(true)
                if not self._loggedWidgets then
                    self._loggedWidgets = true
                    local n = self.frameName
                    local sf = n and _G[n .. "ScrollFrame"]
                    local sc = n and _G[n .. "ScrollFrameScrollChild"]
                    addon:debug(L.LogLoggerUIWidgets:format(
                        tostring(cfg.keyName or "?"),
                        tostring(sf), tostring(sc),
                        sf and (sf:GetWidth() or 0) or 0,
                        sf and (sf:GetHeight() or 0) or 0,
                        sc and (sc:GetWidth() or 0) or 0,
                        sc and (sc:GetHeight() or 0) or 0
                    ))
                end
            end)

            frame:SetScript("OnHide", function()
                setActive(false)
            end)

            if frame:IsShown() then
                setActive(true)
            end
        end

        function self:Fetch()
            local n = self.frameName
            if not n then return end

            local sf = _G[n .. "ScrollFrame"]
            local sc = _G[n .. "ScrollFrameScrollChild"]
            if not (sf and sc) then
                if not self._missingScroll then
                    self._missingScroll = true
                    addon:warn(L.LogLoggerUIMissingWidgets:format(tostring(cfg.keyName or "?"), tostring(n)))
                end
                return
            end

            local scrollW = sf:GetWidth() or 0
            local widthChanged = (self._lastWidth ~= scrollW)
            self._lastWidth = scrollW

            -- Defer draw until the ScrollFrame has a real size (first OnShow can report 0).
            if scrollW < 10 then
                if not self._warnW0 then
                    self._warnW0 = true
                    addon:debug(L.LogLoggerUIDeferLayout:format(tostring(cfg.keyName or "?"), scrollW))
                end
                defer:Show()
                return false
            end
            if (sc:GetWidth() or 0) < 10 then
                sc:SetWidth(scrollW)
            end

            -- One-time diagnostics per list to help debug "empty/blank" frames.
            if not self._loggedFetch then
                self._loggedFetch = true
                addon:debug(L.LogLoggerUIFetch:format(
                    tostring(cfg.keyName or "?"),
                    #self.data,
                    sf:GetWidth() or 0, sf:GetHeight() or 0,
                    sc:GetWidth() or 0, sc:GetHeight() or 0,
                    (_G[n] and _G[n]:GetWidth() or 0),
                    (_G[n] and _G[n]:GetHeight() or 0)
                ))
            end

            local totalH = 0
            local count = #self.data

            for i = 1, count do
                local it = self.data[i]
                local btnName = cfg.rowName(n, it, i)

                local row = self._rows[i]
                if not row or row:GetName() ~= btnName then
                    row = acquireRow(btnName, sc)
                    self._rows[i] = row
                end

                row:SetID(it.id)
                row:ClearAllPoints()
                -- Stretch the row to the scrollchild width.
                -- (Avoid relying on GetWidth() being valid on the first OnShow frame.)
                row:SetPoint("TOPLEFT", 0, -totalH)
                row:SetPoint("TOPRIGHT", -20, -totalH)

                local rH = cfg.drawRow(row, it)
                local usedH = rH or row:GetHeight() or 20
                totalH = totalH + usedH

                row:Show()
            end

            for i = count + 1, #self._rows do
                local r = self._rows[i]
                if r then r:Hide() end
            end

            sc:SetHeight(math_max(totalH, sf:GetHeight()))
            if sf.UpdateScrollChildRect then
                sf:UpdateScrollChildRect()
            end
            self._lastHL = nil
        end

        function self:Sort(key)
            local cmp = cfg.sorters and cfg.sorters[key]
            if not cmp or #self.data <= 1 then return end
            self._asc = not self._asc
            table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
            self:Fetch()
            applyHighlight()
            postUpdate()
        end

        self._makeConfirmPopup = Utils.makeConfirmPopup

        return self
    end

    function bindLoggerListController(module, controller)
        module.OnLoad = function(_, frame) controller:OnLoad(frame) end
        module.Fetch = function() controller:Fetch() end
        module.Sort = function(_, t) controller:Sort(t) end
    end
end

-- ============================================================================
-- Raids List
-- ============================================================================
do
    addon.Logger.Raids = addon.Logger.Raids or {}
    local Raids = addon.Logger.Raids
    local L = addon.L

    local controller = makeLoggerListController {
        keyName = "RaidsList",
        poolTag = "logger-raids",
        _rowParts = { "ID", "Date", "Zone", "Size" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidsList) end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderDate"]:SetText(L.StrDate)
            _G[n .. "HeaderZone"]:SetText(L.StrZone)
            _G[n .. "HeaderSize"]:SetText(L.StrSize)
            _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            addon:SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
            _G[n .. "ExportBtn"]:Disable() -- non implementato
        end,

        getData = function(out)
            for i = 1, #KRT_Raids do
                local r = KRT_Raids[i]
                local it = {}
                it.id = i
                it.zone = r.zone
                it.size = r.size
                it.date = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "RaidBtn" .. i end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.ID:SetText(it.id)
                ui.Date:SetText(it.dateFmt)
                ui.Zone:SetText(it.zone)
                ui.Size:SetText(it.size)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedRaid end,

        postUpdate = function(n)
            local sel = addon.Logger.selectedRaid
            local raidSize = addon.Raid:GetRaidSize()
            local canSetCurrent = sel
                and sel ~= KRT_CurrentRaid
                and not addon.Raid:Expired(sel)
                and (raidSize == 0 or raidSize == KRT_Raids[sel].size)

            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)
            Utils.enableDisable(_G[n .. "DeleteBtn"], (sel ~= KRT_CurrentRaid))
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    bindLoggerListController(Raids, controller)

    function Raids:SetCurrent(btn)
        local sel = addon.Logger.selectedRaid
        if not (btn and sel and KRT_Raids[sel]) then return end

        local raidSize = addon.Raid:GetRaidSize()
        if raidSize ~= 0 and KRT_Raids[sel].size ~= raidSize then
            addon:error(L.ErrCannotSetCurrentRaidSize)
            return
        end
        if addon.Raid:Expired(sel) then
            addon:error(L.ErrCannotSetCurrentRaidReset)
            return
        end
        KRT_CurrentRaid = sel
        controller:Touch()
    end

    do
        local function DeleteRaid()
            local sel = addon.Logger.selectedRaid
            if not (sel and KRT_Raids[sel]) then return end
            if KRT_CurrentRaid and KRT_CurrentRaid == sel then
                addon:error(L.ErrCannotDeleteRaid)
                return
            end

            tremove(KRT_Raids, sel)
            if KRT_CurrentRaid and KRT_CurrentRaid > sel then
                KRT_CurrentRaid = KRT_CurrentRaid - 1
            end

            addon.Logger.selectedRaid = nil
            controller:Dirty()
        end

        function Raids:Delete(btn)
            if btn and addon.Logger.selectedRaid ~= nil then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaid)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        addon.Logger.selectedRaid = tonumber(num)
        controller:Dirty()
    end)

    Utils.registerCallback("LoggerSelectRaid", function() controller:Touch() end)
end

-- ============================================================================
-- Boss List
-- ============================================================================
do
    addon.Logger.Boss = addon.Logger.Boss or {}
    local Boss = addon.Logger.Boss
    local L = addon.L

    local function getBossModeLabel(bossData)
        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        return (mode == "h") and "H" or "N"
    end

    local controller = makeLoggerListController {
        keyName = "BossList",
        poolTag = "logger-bosses",
        _rowParts = { "ID", "Name", "Time", "Mode" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBosses) end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
            _G[n .. "HeaderMode"]:SetText(L.StrMode)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local raid = KRT_Raids[rID]
            if not raid or not raid.bossKills then return end

            for i = 1, #raid.bossKills do
                local boss = raid.bossKills[i]
                local it = {}
                it.id = i
                it.name = boss.name
                it.time = boss.time or boss.date
                it.timeFmt = date("%H:%M", it.time or time())
                it.mode = getBossModeLabel(boss)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "BossBtn" .. i end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.ID:SetText(it.id)
                ui.Name:SetText(it.name)
                ui.Time:SetText(it.timeFmt)
                ui.Mode:SetText(it.mode)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedBoss end,

        postUpdate = function(n)
            local hasRaid = addon.Logger.selectedRaid
            local hasBoss = addon.Logger.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            Utils.enableDisable(_G[n .. "DeleteBtn"], hasBoss ~= nil)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.id < b.id) or (a.id > b.id) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    bindLoggerListController(Boss, controller)

    function Boss:Add() addon.Logger.BossBox:Toggle() end

    function Boss:Edit() if addon.Logger.selectedBoss then addon.Logger.BossBox:Fill() end end

    do
        local function DeleteBoss()
            local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
            if not (rID and bID and KRT_Raids[rID]) then return end

            local lootRemoved = 0
            local raid = KRT_Raids[rID]
            local loot = raid.loot or {}
            for i = #loot, 1, -1 do
                if loot[i].bossNum == bID then
                    tremove(loot, i)
                    lootRemoved = lootRemoved + 1
                end
            end

            tremove(raid.bossKills, bID)
            addon:info(L.LogLoggerBossLootRemoved, rID, bID, lootRemoved)

            addon.Logger.selectedBoss = nil
            addon.Logger:ResetSelections()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end

        function Boss:Delete()
            if addon.Logger.selectedBoss then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBoss)
    end

    function Boss:GetName(bossId, raidId)
        local rID = raidId or addon.Logger.selectedRaid
        if not rID or not bossId or not KRT_Raids[rID] then return "" end
        local boss = KRT_Raids[rID].bossKills[bossId]
        return boss and boss.name or ""
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBoss", function() controller:Touch() end)
end

-- ============================================================================
-- Boss Attendees List
-- ============================================================================
do
    addon.Logger.BossAttendees = addon.Logger.BossAttendees or {}
    local BossAtt = addon.Logger.BossAttendees
    local L = addon.L

    local controller = makeLoggerListController {
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBossAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            if not (rID and bID) then return end

            local src = addon.Raid:GetPlayers(rID, bID, {})
            for i = 1, #src do
                local p = src[i]
                local it = {}
                it.id = p.id
                it.name = p.name
                it.class = p.class
                out[i] = it
            end
            twipe(src)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                local r, g, b = Utils.getClassColor(it.class)
                ui.Name:SetText(it.name)
                ui.Name:SetVertexColor(r, g, b)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedBossPlayer end,

        postUpdate = function(n)
            local bSel = addon.Logger.selectedBoss
            local pSel = addon.Logger.selectedBossPlayer
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            if addBtn then
                Utils.enableDisable(addBtn, bSel and not pSel)
            end
            if removeBtn then
                Utils.enableDisable(removeBtn, bSel and pSel)
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    bindLoggerListController(BossAtt, controller)

    function BossAtt:Add() addon.Logger.AttendeesBox:Toggle() end

    do
        local function DeleteAttendee()
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer
            if not (rID and bID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.bossKills and raid.bossKills[bID]) then return end

            local name = addon.Raid:GetPlayerName(pID, rID)
            local list = raid.bossKills[bID].players
            local i = addon.tIndexOf(list, name)
            while i do
                tremove(list, i)
                i = addon.tIndexOf(list, name)
            end

            addon.Logger.selectedBossPlayer = nil
            controller:Dirty()
        end

        function BossAtt:Delete()
            if addon.Logger.selectedBossPlayer then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallbacks({ "LoggerSelectRaid", "LoggerSelectBoss" }, function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBossPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Raid Attendees List
-- ============================================================================
do
    addon.Logger.RaidAttendees = addon.Logger.RaidAttendees or {}
    local RaidAtt = addon.Logger.RaidAttendees
    local L = addon.L

    local controller = makeLoggerListController {
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            _G[n .. "AddBtn"]:Disable()
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local src = addon.Raid:GetPlayers(rID) or {}
            for i = 1, #src do
                local p = src[i]
                local it = {}
                it.id = p.id
                it.name = p.name
                it.class = p.class
                it.join = p.join
                it.leave = p.leave
                it.joinFmt = date("%H:%M", p.join)
                it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = (function()
            local ROW_H
            return function(row, it)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p
                ui.Name:SetText(it.name)
                local r, g, b = Utils.getClassColor(it.class)
                ui.Name:SetVertexColor(r, g, b)
                ui.Join:SetText(it.joinFmt)
                ui.Leave:SetText(it.leaveFmt)
                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedPlayer end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            if deleteBtn then
                Utils.enableDisable(deleteBtn, addon.Logger.selectedPlayer ~= nil)
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            join = function(a, b, asc) return asc and (a.join < b.join) or (a.join > b.join) end,
            leave = function(a, b, asc)
                local A = a.leave or (asc and math.huge or -math.huge)
                local B = b.leave or (asc and math.huge or -math.huge)
                return asc and (A < B) or (A > B)
            end,
        },
    }

    bindLoggerListController(RaidAtt, controller)

    do
        local function DeleteAttendee()
            local rID, pID = addon.Logger.selectedRaid, addon.Logger.selectedPlayer
            if not (rID and pID) then return end

            local raid = KRT_Raids[rID]
            if not (raid and raid.players and raid.players[pID]) then return end

            local name = raid.players[pID].name
            tremove(raid.players, pID)

            for _, boss in ipairs(raid.bossKills) do
                local i = addon.tIndexOf(boss.players, name)
                while i do
                    tremove(boss.players, i)
                    i = addon.tIndexOf(boss.players, name)
                end
            end

            for i = #raid.loot, 1, -1 do
                if raid.loot[i].looter == name then
                    tremove(raid.loot, i)
                end
            end

            addon.Logger.selectedPlayer = nil
            controller:Dirty()
        end

        function RaidAtt:Delete()
            if addon.Logger.selectedPlayer then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendee)
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectPlayer", function() controller:Touch() end)
end

-- ============================================================================
-- Loot List (filters by selected boss and player)
-- ============================================================================
do
    addon.Logger.Loot = addon.Logger.Loot or {}
    local Loot = addon.Logger.Loot
    local L = addon.L

    local function isLootFromBoss(entry, bossId)
        return not bossId or bossId <= 0 or entry.bossNum == bossId
    end

    local function isLootByPlayer(entry, playerName)
        return not playerName or entry.looter == playerName
    end

    local function passesFilters(entry, bossId, playerName)
        return isLootFromBoss(entry, bossId) and isLootByPlayer(entry, playerName)
    end

    local controller = makeLoggerListController {
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidLoot) end
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            _G[n .. "ClearBtn"]:SetText(L.BtnClear)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "HeaderItem"]:SetText(L.StrItem)
            _G[n .. "HeaderSource"]:SetText(L.StrSource)
            _G[n .. "HeaderWinner"]:SetText(L.StrWinner)
            _G[n .. "HeaderType"]:SetText(L.StrType)
            _G[n .. "HeaderRoll"]:SetText(L.StrRoll)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)

            -- disabilitati finché non implementati
            _G[n .. "ExportBtn"]:Disable()
            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            _G[n .. "EditBtn"]:Disable()
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            if not rID then return end

            local loot = addon.Raid:GetLoot(rID) or {}

            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer or addon.Logger.selectedPlayer
            local pName = pID and addon.Raid:GetPlayerName(pID, rID) or nil

            local n = 0
            for i = 1, #loot do
                local v = loot[i]
                if passesFilters(v, bID, pName) then
                    n = n + 1
                    local it = {}
                    it.id = v.id
                    it.itemId = v.itemId
                    it.itemName = v.itemName
                    it.itemRarity = v.itemRarity
                    it.itemTexture = v.itemTexture
                    it.itemLink = v.itemLink
                    it.bossNum = v.bossNum
                    it.looter = v.looter
                    it.rollType = tonumber(v.rollType) or 0
                    it.rollValue = v.rollValue
                    it.time = v.time
                    it.timeFmt = date("%H:%M", v.time)
                    out[n] = it
                end
            end
        end,

        rowName = function(n, _, i) return n .. "ItemBtn" .. i end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = (function()
            local ROW_H
            return function(row, v)
                if not ROW_H then ROW_H = (row and row:GetHeight()) or 20 end
                local ui = row._p

                row._itemLink = v.itemLink
                local nameText = v.itemLink or v.itemName or ("[Item " .. (v.itemId or "?") .. "]")
                if v.itemLink then
                    ui.Name:SetText(nameText)
                else
                    ui.Name:SetText(addon.WrapTextInColorCode(
                        nameText,
                        Utils.normalizeHexColor(itemColors[(v.itemRarity or 1) + 1])
                    ))
                end

                local selectedBoss = addon.Logger.selectedBoss
                if selectedBoss and v.bossNum == selectedBoss then
                    ui.Source:SetText("")
                else
                    ui.Source:SetText(addon.Logger.Boss:GetName(v.bossNum, addon.Logger.selectedRaid))
                end

                local r, g, b = Utils.getClassColor(addon.Raid:GetPlayerClass(v.looter))
                ui.Winner:SetText(v.looter)
                ui.Winner:SetVertexColor(r, g, b)

                local rt = tonumber(v.rollType) or 0
                v.rollType = rt
                ui.Type:SetText(lootTypesColored[rt] or lootTypesColored[4])
                ui.Roll:SetText(v.rollValue or 0)
                ui.Time:SetText(v.timeFmt)

                local icon = v.itemTexture
                if not icon and v.itemId then
                    icon = GetItemIcon(v.itemId)
                end
                if not icon then
                    icon = C.RESERVES_ITEM_FALLBACK_ICON
                end
                ui.ItemIconTexture:SetTexture(icon)

                return ROW_H
            end
        end)(),

        highlightId = function() return addon.Logger.selectedItem end,

        postUpdate = function(n)
            Utils.enableDisable(_G[n .. "DeleteBtn"], addon.Logger.selectedItem ~= nil)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc) return asc and (a.bossNum < b.bossNum) or (a.bossNum > b.bossNum) end,
            winner = function(a, b, asc) return asc and (a.looter < b.looter) or (a.looter > b.looter) end,
            type = function(a, b, asc) return asc and (a.rollType < b.rollType) or (a.rollType > b.rollType) end,
            roll = function(a, b, asc)
                local A = a.rollValue or 0
                local B = b.rollValue or 0
                return asc and (A < B) or (A > B)
            end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
        },
    }

    bindLoggerListController(Loot, controller)

    function Loot:OnEnter(widget)
        if not widget then return end
        local row = (widget.IsObjectType and widget:IsObjectType("Button")) and widget
            or (widget.GetParent and widget:GetParent()) or widget
        if not (row and row.GetID) then return end

        local link = row._itemLink
        if not link then return end

        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(link)
    end

    do
        local function DeleteItem()
            local rID, iID = addon.Logger.selectedRaid, addon.Logger.selectedItem
            if rID and KRT_Raids[rID] and iID then
                tremove(KRT_Raids[rID].loot, iID)
                addon.Logger.selectedItem = nil
                controller:Dirty()
            end
        end

        function Loot:Delete()
            if addon.Logger.selectedItem then
                StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ITEM", L.StrConfirmDeleteItem, DeleteItem)
    end

    function Loot:Log(itemID, looter, rollType, rollValue, source, raidIDOverride)
        local raidID
        if raidIDOverride then
            raidID = raidIDOverride
        else
            -- If the Logger window is open and browsing an old raid, selectedRaid may differ from KRT_CurrentRaid.
            -- Runtime sources must always write into the CURRENT raid session, while Logger UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = addon.Logger.selectedRaid or KRT_CurrentRaid
            else
                raidID = KRT_CurrentRaid or addon.Logger.selectedRaid
            end
        end
        addon:trace(L.LogLoggerLootLogAttempt:format(tostring(source), tostring(raidID), tostring(itemID),
            tostring(looter), tostring(rollType), tostring(rollValue), tostring(KRT_LastBoss)))
        if not raidID or not KRT_Raids[raidID] then
            addon:error(L.LogLoggerNoRaidSession:format(tostring(raidID), tostring(itemID)))
            return false
        end

        local raid = KRT_Raids[raidID]
        local lootCount = raid.loot and #raid.loot or 0
        local it = raid.loot[itemID]
        if not it then
            addon:error(L.LogLoggerItemNotFound:format(raidID, tostring(itemID), lootCount))
            return false
        end

        if not looter or looter == "" then
            addon:warn(L.LogLoggerLooterEmpty:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(L.LogLoggerRollTypeNil:format(raidID, tostring(itemID), tostring(looter)))
        end

        addon:debug(L.LogLoggerLootBefore:format(raidID, tostring(itemID), tostring(it.itemLink),
            tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))
        if it.looter and it.looter ~= "" and looter and looter ~= "" and it.looter ~= looter then
            addon:warn(L.LogLoggerLootOverwrite:format(raidID, tostring(itemID), tostring(it.itemLink),
                tostring(it.looter), tostring(looter)))
        end

        local expectedLooter
        local expectedRollType
        local expectedRollValue
        if looter and looter ~= "" then
            it.looter = looter
            expectedLooter = looter
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
        addon:info(L.LogLoggerLootRecorded:format(tostring(source), raidID, tostring(itemID),
            tostring(it.itemLink), tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))

        local ok = true
        if expectedLooter and it.looter ~= expectedLooter then ok = false end
        if expectedRollType and it.rollType ~= expectedRollType then ok = false end
        if expectedRollValue and it.rollValue ~= expectedRollValue then ok = false end
        if not ok then
            addon:error(L.LogLoggerVerifyFailed:format(raidID, tostring(itemID), tostring(it.looter),
                tostring(it.rollType), tostring(it.rollValue)))
            return false
        end

        addon:debug(L.LogLoggerVerified:format(raidID, tostring(itemID)))
        if not KRT_LastBoss then
            addon:info(L.LogLoggerRecordedNoBossContext:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        return true
    end

    local function Reset() controller:Dirty() end
    Utils.registerCallbacks(
        { "LoggerSelectRaid", "LoggerSelectBoss", "LoggerSelectPlayer", "LoggerSelectBossPlayer",
            "RaidLootUpdate" },
        Reset
    )
    Utils.registerCallback("LoggerSelectItem", function() controller:Touch() end)
end

-- ============================================================================
-- Logger: Add/Edit Boss Popup  (Patch #1 — uniforma a time/mode)
-- ============================================================================
do
    addon.Logger.BossBox = addon.Logger.BossBox or {}
    local Box = addon.Logger.BossBox
    local L = addon.L

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local updateInterval = C.UPDATE_INTERVAL_LOGGER

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnUpdate", function(_, elapsed) self:UpdateUIFrame(_, elapsed) end)
        frame:SetScript("OnHide", function() self:CancelAddEdit() end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Hide()
        local f = _G[frameName]
        Utils.setShown(f, false)
    end

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        if not (rID and bID) then return end

        raidData = KRT_Raids[rID]
        if not raidData then return end

        bossData = raidData.bossKills[bID]
        if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name or "")

        local bossTime = bossData.time or bossData.date or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        _G[frameName .. "Time"]:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        _G[frameName .. "Difficulty"]:SetText((mode == "h") and "h" or "n")

        isEdit = true
        self:Toggle()
    end

    function Box:Save()
        local rID = addon.Logger.selectedRaid
        if not rID then return end

        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        local modeT = Utils.normalizeLower(_G[frameName .. "Difficulty"]:GetText())
        local bTime = Utils.trimText(_G[frameName .. "Time"]:GetText())

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

        if isEdit and bossData then
            bossData.name = name
            bossData.time = time(killDate)
            bossData.mode = mode
        else
            tinsert(KRT_Raids[rID].bossKills, {
                name = name,
                time = time(killDate),
                mode = mode,
                players = {},
            })
        end

        self:Hide()
        addon.Logger:ResetSelections()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end

    function Box:CancelAddEdit()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Difficulty"])
        Utils.resetEditBox(_G[frameName .. "Time"])
        isEdit, raidData, bossData = false, {}, {}
        twipe(tempDate)
    end

    function Box:UpdateUIFrame(frame, elapsed)
        if not localized then
            addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        Utils.throttledUIUpdate(frame, frameName, updateInterval, elapsed, function()
            Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
        end)
    end
end

-- ============================================================================
-- Logger: Add Attendee Popup
-- ============================================================================
do
    addon.Logger.AttendeesBox = addon.Logger.AttendeesBox or {}
    local Box = addon.Logger.AttendeesBox
    local L = addon.L

    local frameName

    function Box:OnLoad(frame)
        if not frame then return end
        frameName = frame:GetName()
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnShow", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
        frame:SetScript("OnHide", function()
            Utils.resetEditBox(_G[frameName .. "Name"])
        end)
    end

    function Box:Toggle() Utils.toggle(_G[frameName]) end

    function Box:Save()
        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        local normalizedName = Utils.normalizeLower(name)
        if normalizedName == "" then
            addon:error(L.ErrAttendeesInvalidName)
            return
        end

        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        if not (rID and bID and KRT_Raids[rID]) then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return
        end

        local bossKill = KRT_Raids[rID].bossKills[bID]
        for _, n in ipairs(bossKill.players) do
            if Utils.normalizeLower(n) == normalizedName then
                addon:error(L.ErrAttendeesPlayerExists)
                return
            end
        end

        for _, p in ipairs(KRT_Raids[rID].players) do
            if normalizedName == Utils.normalizeLower(p.name) then
                tinsert(bossKill.players, p.name)
                addon:info(L.StrAttendeesAddSuccess)
                self:Toggle()
                Utils.triggerEvent("LoggerSelectBoss", addon.Logger.selectedBoss)
                return
            end
        end

        addon:error(L.ErrAttendeesInvalidName)
    end
end
---============================================================================
