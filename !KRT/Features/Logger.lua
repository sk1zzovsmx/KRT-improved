--[[
    Features/Logger.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local C = feature.C

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide
local makeModuleFrameGetter = feature.makeModuleFrameGetter

local rollTypes = feature.rollTypes
local lootTypesColored = feature.lootTypesColored
local itemColors = feature.itemColors

local _G = _G
local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber

-- =========== Logger Frame =========== --
-- Shown loot logger for raids
do
    addon.Logger   = addon.Logger or {}
    local module   = addon.Logger

    -- ----- Internal state ----- --
    local frameName
    local getFrame = makeModuleFrameGetter(module, "KRTLogger")
    -- module: stable-ID data helpers (fresh SavedVariables only; no legacy migration)
    module.Store   = module.Store or {}
    module.View    = module.View or {}
    module.Actions = module.Actions or {}

    local Store    = module.Store
    local View     = module.View
    local Actions  = module.Actions

    -- ----- Private helpers ----- --
    local function normalizeNid(v)
        return tonumber(v) or v
    end

    local function buildIndex(raid, listField, idField, cacheField)
        local list = raid[listField] or {}
        local m = {}
        for i = 1, #list do
            local e = list[i]
            local id = e and e[idField]
            if id ~= nil then
                m[normalizeNid(id)] = i
            end
        end
        raid[cacheField] = m
    end

    local function getIndexedPositionByNid(raid, queryNid, listField, idField, cacheField)
        if not (raid and queryNid) then return nil end

        local normalizedNid = normalizeNid(queryNid)
        if not raid[cacheField] then
            buildIndex(raid, listField, idField, cacheField)
        end

        local idx = raid[cacheField][normalizedNid]
        if not idx then
            -- Raid changed since last build (new entry added / list changed)
            buildIndex(raid, listField, idField, cacheField)
            idx = raid[cacheField][normalizedNid]
        end
        return idx
    end

    -- ----- Public methods ----- --
    -- Ensure the raid table has the schema v2 fields required by the module.
    -- This does NOT migrate legacy structures; it only initializes missing fields for fresh SV.
    function Store:EnsureRaid(raid)
        if not raid then return end
        raid.players       = raid.players or {}
        raid.bossKills     = raid.bossKills or {}
        raid.loot          = raid.loot or {}
        raid.nextBossNid   = raid.nextBossNid or 1
        raid.nextLootNid   = raid.nextLootNid or 1

        -- Runtime-only indexes (not persisted).
        raid._bossIdxByNid = raid._bossIdxByNid or nil
        raid._lootIdxByNid = raid._lootIdxByNid or nil
    end

    function Store:GetRaid(rID)
        local raid = rID and KRT_Raids[rID] or nil
        if raid then self:EnsureRaid(raid) end
        return raid
    end

    function Store:InvalidateIndexes(raid)
        if not raid then return end
        raid._bossIdxByNid = nil
        raid._lootIdxByNid = nil
    end

    function Store:BossIdx(raid, bossNid)
        return getIndexedPositionByNid(raid, bossNid, "bossKills", "bossNid", "_bossIdxByNid")
    end

    function Store:LootIdx(raid, lootNid)
        return getIndexedPositionByNid(raid, lootNid, "loot", "lootNid", "_lootIdxByNid")
    end

    function Store:GetBoss(raid, bossNid)
        local idx = self:BossIdx(raid, bossNid)
        return idx and raid.bossKills[idx] or nil, idx
    end

    function Store:GetLoot(raid, lootNid)
        local idx = self:LootIdx(raid, lootNid)
        return idx and raid.loot[idx] or nil, idx
    end

    function Store:FindRaidPlayerByNormName(raid, normalizedLower)
        if not (raid and normalizedLower) then return nil end
        local players = raid.players or {}
        for i = 1, #players do
            local p = players[i]
            if p and p.name and Utils.normalizeLower(p.name) == normalizedLower then
                return p.name, i, p
            end
        end
        return nil
    end

    function View:GetBossModeLabel(bossData)
        if not bossData then return "?" end
        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        return (mode == "h") and "H" or "N"
    end

    function View:BuildRows(out, list, pred, map)
        if not out then return end
        twipe(out)
        if not list then return end
        local n = 0
        for i = 1, #list do
            local e = list[i]
            if (not pred) or pred(e, i) then
                n = n + 1
                out[n] = map(e, i, n)
            end
        end
    end

    function View:FillBossList(out, raid)
        self:BuildRows(out, raid and raid.bossKills, nil, function(boss, i)
            local it = {}
            -- Stable NID used for highlight/selection.
            it.id = tonumber(boss and boss.bossNid) or (boss and boss.bossNid) or i
            -- Display-only index (rescales after deletions).
            it.seq = i
            it.name = boss and boss.name or ""
            it.time = boss and boss.time or time()
            it.timeFmt = date("%H:%M", it.time)
            it.mode = self:GetBossModeLabel(boss)
            return it
        end)
    end

    function View:FillRaidAttendeesList(out, raid)
        self:BuildRows(out, raid and raid.players, nil, function(p, i)
            local it = {}
            it.id = i
            it.name = p.name
            it.class = p.class
            it.join = p.join
            it.leave = p.leave
            it.joinFmt = p.join and date("%H:%M", p.join) or ""
            it.leaveFmt = p.leave and date("%H:%M", p.leave) or ""
            return it
        end)
    end

    function View:FillBossAttendeesList(out, raid, bossNid)
        if not out then return end
        twipe(out)
        if not (raid and bossNid) then return end
        local bossKill = Store:GetBoss(raid, bossNid)
        if not (bossKill and bossKill.players and raid.players) then return end

        -- Build a set for O(1) membership checks.
        local set = {}
        for i = 1, #bossKill.players do
            local name = bossKill.players[i]
            if name then set[name] = true end
        end

        local n = 0
        for i = 1, #raid.players do
            local p = raid.players[i]
            if p and p.name and set[p.name] then
                n = n + 1
                local it = {}
                it.id = i -- IMPORTANT: stable reference into raid.players (used for delete)
                it.name = p.name
                it.class = p.class
                out[n] = it
            end
        end
    end

    function View:FillLootList(out, raid, bossNid, playerName)
        local bossFilter = tonumber(bossNid) or bossNid
        self:BuildRows(out, raid and raid.loot,
            function(v)
                if not v then return false end
                local okBoss = (not bossFilter) or (bossFilter <= 0) or (tonumber(v.bossNid) == bossFilter)
                local okPlayer = (not playerName) or (v.looter == playerName)
                return okBoss and okPlayer
            end,
            function(v)
                local it = {}
                it.id = v.lootNid
                it.itemId = v.itemId
                it.itemName = v.itemName
                it.itemRarity = v.itemRarity
                it.itemTexture = v.itemTexture
                it.itemLink = v.itemLink
                it.bossNid = v.bossNid
                it.looter = v.looter
                it.rollType = tonumber(v.rollType) or 0
                it.rollValue = v.rollValue
                it.time = v.time or time()
                it.timeFmt = date("%H:%M", it.time)
                return it
            end
        )
    end

    function Actions:RemoveAll(list, value)
        if not (list and value) then return end
        local i = addon.tIndexOf(list, value)
        while i do
            tremove(list, i)
            i = addon.tIndexOf(list, value)
        end
    end

    function Actions:Commit(raid, opts)
        if not raid then return end
        opts = opts or {}

        if opts.invalidate ~= false then
            Store:InvalidateIndexes(raid)
        end

        local log = addon.Logger
        if not log then return end

        local changedBoss, changedPlayer, changedBossPlayer, changedItem = false, false, false, false

        local function clearBossSelection()
            if log.selectedBoss ~= nil then changedBoss = true end
            if log.selectedBossPlayer ~= nil then changedBossPlayer = true end
            if log.selectedItem ~= nil then changedItem = true end
            log.selectedBoss = nil
            log.selectedBossPlayer = nil
            log.selectedItem = nil
        end

        -- Validate boss selection (bossNid)
        if log.selectedBoss then
            local bossKill = Store:GetBoss(raid, log.selectedBoss)
            if not bossKill then
                clearBossSelection()
            end
        else
            -- No boss selected: dependent selections must be cleared
            if log.selectedBossPlayer ~= nil then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
            if log.selectedItem ~= nil then
                log.selectedItem = nil
                changedItem = true
            end
        end

        -- Validate loot selection (lootNid)
        if log.selectedItem then
            local lootEntry = Store:GetLoot(raid, log.selectedItem)
            if not lootEntry then
                log.selectedItem = nil
                changedItem = true
            end
        end

        -- Validate player selections (raid.players index)
        if opts.clearPlayers then
            if log.selectedPlayer ~= nil then
                log.selectedPlayer = nil
                changedPlayer = true
            end
            if log.selectedBossPlayer ~= nil then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
        else
            if log.selectedPlayer and (not raid.players or not raid.players[log.selectedPlayer]) then
                log.selectedPlayer = nil
                changedPlayer = true
            end
            if log.selectedBossPlayer and (not raid.players or not raid.players[log.selectedBossPlayer]) then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
        end

        if changedBoss then Utils.triggerEvent("LoggerSelectBoss", log.selectedBoss) end
        if changedPlayer then Utils.triggerEvent("LoggerSelectPlayer", log.selectedPlayer) end
        if changedBossPlayer then Utils.triggerEvent("LoggerSelectBossPlayer", log.selectedBossPlayer) end
        if changedItem then Utils.triggerEvent("LoggerSelectItem", log.selectedItem) end
    end

    function Actions:DeleteBoss(rID, bossNid)
        local raid = Store:GetRaid(rID)
        if not (raid and bossNid) then return 0 end

        local _, bossIndex = Store:GetBoss(raid, bossNid)
        if not bossIndex then return 0 end

        local removed = 0
        for i = #raid.loot, 1, -1 do
            local l = raid.loot[i]
            if l and tonumber(l.bossNid) == tonumber(bossNid) then
                tremove(raid.loot, i)
                removed = removed + 1
            end
        end

        tremove(raid.bossKills, bossIndex)
        self:Commit(raid)

        if KRT_CurrentRaid == rID and tonumber(KRT_LastBoss) == tonumber(bossNid) then
            KRT_LastBoss = nil
        end

        return removed
    end

    function Actions:DeleteLoot(rID, lootNid)
        local raid = Store:GetRaid(rID)
        if not (raid and lootNid) then return false end
        local _, lootIndex = Store:GetLoot(raid, lootNid)
        if not lootIndex then return false end
        tremove(raid.loot, lootIndex)
        self:Commit(raid)
        return true
    end

    -- Bulk delete: removes multiple loot entries (by nid) with a single Commit()
    -- Returns: number of removed entries
    function Actions:DeleteLootMany(rID, lootNids)
        local raid = Store:GetRaid(rID)
        if not (raid and lootNids and raid.loot) then return 0 end

        local set = {}
        for i = 1, #lootNids do
            local k = lootNids[i]
            if k ~= nil then
                local nk = tonumber(k) or k
                set[nk] = true
            end
        end

        local removed = 0
        for i = #raid.loot, 1, -1 do
            local l = raid.loot[i]
            local nid = l and (tonumber(l.lootNid) or l.lootNid)
            if nid ~= nil and set[nid] then
                tremove(raid.loot, i)
                removed = removed + 1
            end
        end

        if removed > 0 then
            self:Commit(raid)
        end
        return removed
    end

    function Actions:DeleteBossAttendee(rID, bossNid, playerIdx)
        local raid = Store:GetRaid(rID)
        if not (raid and bossNid and playerIdx) then return false end
        local bossKill = Store:GetBoss(raid, bossNid)
        if not (bossKill and bossKill.players and raid.players and raid.players[playerIdx]) then return false end
        local name = raid.players[playerIdx].name
        if not name then return false end
        self:RemoveAll(bossKill.players, name)
        return true
    end

    function Actions:DeleteRaidAttendee(rID, playerIdx)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and raid.players[playerIdx]) then return false end

        local name = raid.players[playerIdx].name

        -- Keep playersByName consistent: mark this record as inactive so UpdateRaidRoster()
        -- can safely rebuild raid.players when needed (e.g. after manual roster edits).
        if name and raid.playersByName and raid.playersByName[name] then
            local p = raid.playersByName[name]
            if p and p.leave == nil then
                p.leave = Utils.getCurrentTime()
            end
        end

        tremove(raid.players, playerIdx)

        -- Remove from all boss attendee lists.
        if name and raid.bossKills then
            for _, boss in ipairs(raid.bossKills) do
                if boss and boss.players then
                    self:RemoveAll(boss.players, name)
                end
            end
        end

        -- Remove loot won by removed player.
        if name and raid.loot then
            for i = #raid.loot, 1, -1 do
                if raid.loot[i] and raid.loot[i].looter == name then
                    tremove(raid.loot, i)
                end
            end
        end

        self:Commit(raid, { clearPlayers = true })
        return true
    end

    -- Bulk delete: removes multiple raid attendees (by playerIdx) with a single Commit()
    -- Returns: number of removed attendees
    function Actions:DeleteRaidAttendeeMany(rID, playerIdxs)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and playerIdxs and #playerIdxs > 0) then return 0 end

        -- Normalize + sort descending (indices shift on removal).
        local ids = {}
        local seen = {}
        for i = 1, #playerIdxs do
            local v = tonumber(playerIdxs[i]) or playerIdxs[i]
            if v and not seen[v] then
                seen[v] = true
                tinsert(ids, v)
            end
        end
        table.sort(ids, function(a, b) return a > b end)

        -- Collect names + remove players from raid.players.
        local removedNames = {}
        local removed = 0
        for i = 1, #ids do
            local idx = ids[i]
            local p = raid.players[idx]
            if p and p.name then
                removedNames[p.name] = true
                tremove(raid.players, idx)
                removed = removed + 1
            end
        end

        if removed == 0 then return 0 end

        -- Keep playersByName consistent: mark removed names as inactive so UpdateRaidRoster()
        -- can re-add current raid members after manual roster edits.
        if raid.playersByName then
            local now = Utils.getCurrentTime()
            for n, _ in pairs(removedNames) do
                local p = raid.playersByName[n]
                if p and p.leave == nil then
                    p.leave = now
                end
            end
        end

        -- Remove from all boss attendee lists.
        if raid.bossKills then
            for _, boss in ipairs(raid.bossKills) do
                if boss and boss.players then
                    for j = #boss.players, 1, -1 do
                        if removedNames[boss.players[j]] then
                            tremove(boss.players, j)
                        end
                    end
                end
            end
        end

        -- Remove loot won by removed players.
        if raid.loot then
            for j = #raid.loot, 1, -1 do
                if raid.loot[j] and removedNames[raid.loot[j].looter] then
                    tremove(raid.loot, j)
                end
            end
        end

        self:Commit(raid, { clearPlayers = true })
        return removed
    end

    function Actions:DeleteRaid(rID)
        local sel = tonumber(rID)
        if not sel or not KRT_Raids[sel] then return false end

        if KRT_CurrentRaid and KRT_CurrentRaid == sel then
            addon:error(L.ErrCannotDeleteRaid)
            return false
        end

        tremove(KRT_Raids, sel)

        if KRT_CurrentRaid and KRT_CurrentRaid > sel then
            KRT_CurrentRaid = KRT_CurrentRaid - 1
        end

        return true
    end

    function Actions:SetCurrentRaid(rID)
        local sel = tonumber(rID)
        local raid = sel and KRT_Raids[sel] or nil
        if not (sel and raid) then return false end

        -- This is meant to fix duplicate raid creation while actively raiding.
        if not addon.IsInRaid() then
            addon:error(L.ErrCannotSetCurrentNotInRaid)
            return false
        end

        local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
        if isDyn then
            instanceDiff = instanceDiff + (2 * dynDiff)
        end
        if instanceType ~= "raid" then
            addon:error(L.ErrCannotSetCurrentNotInInstance)
            return false
        end
        if raid.zone and raid.zone ~= instanceName then
            addon:error(L.ErrCannotSetCurrentZoneMismatch)
            return false
        end

        local raidDiff = tonumber(raid.difficulty)
        local curDiff = tonumber(instanceDiff)
        if not (raidDiff and curDiff and raidDiff == curDiff) then
            addon:error(L.ErrCannotSetCurrentRaidDifficulty)
            return false
        end

        local raidSize = tonumber(raid.size)
        local groupSize = addon.Raid:GetRaidSize()
        if not raidSize or raidSize ~= groupSize then
            addon:error(L.ErrCannotSetCurrentRaidSize)
            return false
        end

        if addon.Raid:Expired(sel) then
            addon:error(L.ErrCannotSetCurrentRaidReset)
            return false
        end

        KRT_CurrentRaid = sel
        KRT_LastBoss = nil

        -- Sync roster/dropdowns immediately so subsequent logging targets the selected raid.
        addon.Raid:UpdateRaidRoster()

        addon:info(L.LogRaidSetCurrent:format(sel, tostring(raid.zone), raidSize))
        return true
    end

    -- Upsert boss kill (edit if bossNid provided, otherwise append new boss kill).
    -- Returns bossNid on success, nil on failure.
    function Actions:UpsertBossKill(rID, bossNid, name, ts, mode)
        local raid = Store:GetRaid(rID)
        if not raid then return nil end

        name = Utils.trimText(name or "")
        mode = Utils.normalizeLower(mode or "n")
        ts = tonumber(ts) or time()

        if bossNid then
            local bossKill = Store:GetBoss(raid, bossNid)
            if not bossKill then
                addon:error(L.ErrAttendeesInvalidRaidBoss)
                return nil
            end
            bossKill.name = name
            bossKill.time = ts
            bossKill.mode = (mode == "h") and "h" or "n"
            -- keep existing players/hash; hash is stable per nid
            self:Commit(raid, { invalidate = false })
            return bossKill.bossNid
        end

        local newNid = tonumber(raid.nextBossNid) or 1
        raid.nextBossNid = newNid + 1

        tinsert(raid.bossKills, {
            bossNid = newNid,
            name = name,
            time = ts,
            mode = (mode == "h") and "h" or "n",
            players = {},
            hash = Utils.encode(rID .. "|" .. name .. "|" .. newNid),
        })

        self:Commit(raid)
        return newNid
    end

    -- Add existing raid player to the selected boss attendees list.
    -- nameRaw is matched (case-insensitive) against raid.players[].name.
    function Actions:AddBossAttendee(rID, bossNid, nameRaw)
        local name = Utils.trimText(nameRaw or "")
        local normalizedName = Utils.normalizeLower(name)
        if normalizedName == "" then
            addon:error(L.ErrAttendeesInvalidName)
            return false
        end

        local raid = (rID and bossNid) and Store:GetRaid(rID) or nil
        if not (raid and bossNid) then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return false
        end

        local bossKill = Store:GetBoss(raid, bossNid)
        if not bossKill then
            addon:error(L.ErrAttendeesInvalidRaidBoss)
            return false
        end

        bossKill.players = bossKill.players or {}
        for _, n in ipairs(bossKill.players) do
            if Utils.normalizeLower(n) == normalizedName then
                addon:error(L.ErrAttendeesPlayerExists)
                return false
            end
        end

        local playerName = Store:FindRaidPlayerByNormName(raid, normalizedName)
        if playerName then
            tinsert(bossKill.players, playerName)
            addon:info(L.StrAttendeesAddSuccess)
            self:Commit(raid, { invalidate = false })
            return true
        end

        addon:error(L.ErrAttendeesInvalidName)
        return false
    end

    module.selectedRaid = nil
    module.selectedBoss = nil
    module.selectedPlayer = nil
    module.selectedBossPlayer = nil
    module.selectedItem = nil

    -- Multi-select context keys (runtime-only)
    -- NOTE: selection state lives in Utils.lua and is keyed by these context strings.
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

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        module.selectedBoss = nil
        module.selectedPlayer = nil
        module.selectedBossPlayer = nil
        module.selectedItem = nil
        Utils.multiSelectClear(MS_CTX_BOSS)
        Utils.multiSelectClear(MS_CTX_BOSSATT)
        Utils.multiSelectClear(MS_CTX_RAIDATT)
        Utils.multiSelectClear(MS_CTX_LOOT)
    end

    -- Logger helpers: resolve current raid/boss/loot and run raid actions with a single refresh.
    function module:NeedRaid()
        local rID = module.selectedRaid
        local raid = rID and Store:GetRaid(rID) or nil
        return raid, rID
    end

    function module:NeedBoss(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then return nil end
        local bNid = module.selectedBoss
        if not bNid then return nil end
        return Store:GetBoss(raid, bNid)
    end

    function module:NeedLoot(raid)
        raid = raid or (select(1, module:NeedRaid()))
        if not raid then return nil end
        local lNid = module.selectedItem
        if not lNid then return nil end
        return Store:GetLoot(raid, lNid)
    end

    function module:Run(fn, refreshEvent)
        local raid, rID = module:NeedRaid()
        if not raid then return end
        fn(raid, rID)
        if refreshEvent ~= false then
            Utils.triggerEvent(refreshEvent or "LoggerSelectRaid", module.selectedRaid)
        end
    end

    function module:ResetSelections()
        clearSelections()
    end

    function module:OnLoad(frame)
        frameName = Utils.initModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                if not module.selectedRaid then
                    module.selectedRaid = KRT_CurrentRaid
                end
                clearSelections()
                Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
            end,
            hookOnHide = function()
                module.selectedRaid = KRT_CurrentRaid
                clearSelections()
            end,
        })
        if not frameName then return end
        Utils.setFrameTitle(frameName, L.StrLootLogger)
    end

    -- Initialize UI controller for Toggle/Hide.
    local uiController = Utils.bootstrapModuleUi(module, getFrame, function() module:RequestRefresh() end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    function module:Refresh()
        local frame = getFrame()
        if not frame then return end
        if not module.selectedRaid then
            module.selectedRaid = KRT_CurrentRaid
        end
        clearSelections()
        Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
    end

    -- Selectors
    function module:SelectRaid(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedRaid

        local action, count
        if isRange then
            local ordered = addon.Logger.Raids and addon.Logger.Raids._ctrl and addon.Logger.Raids._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_RAID, ordered, id, isMulti)
            -- SHIFT range always sets the focused row to the click target.
            module.selectedRaid = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_RAID, id, isMulti, true)

            -- Keep a single "focused" raid for the dependent panels (Boss / Attendees / Loot).
            if action == "SINGLE_DESELECT" then
                module.selectedRaid = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedRaid == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_RAID)
                    module.selectedRaid = sel[1] or nil
                end
            else
                module.selectedRaid = id
            end

            -- Range anchor (OS-like): update on non-shift clicks only.
            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_RAID, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_RAID, nil)
            end
        end

        if Utils.isDebugEnabled() and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickRaid)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedRaid)
                ))
        end

        -- If the focused raid changed, reset dependent selections (boss/player/loot panels).
        if prevFocus ~= module.selectedRaid then
            clearSelections()
        end

        Utils.triggerEvent("LoggerSelectRaid", module.selectedRaid)
    end

    function module:SelectBoss(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedBoss

        local action, count
        if isRange then
            local ordered = addon.Logger.Boss and addon.Logger.Boss._ctrl and addon.Logger.Boss._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_BOSS, ordered, id, isMulti)
            module.selectedBoss = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_BOSS, id, isMulti, true)

            -- Keep a single "focused" boss for dependent panels (BossAttendees / Loot).
            if action == "SINGLE_DESELECT" then
                module.selectedBoss = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedBoss == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_BOSS)
                    module.selectedBoss = sel[1] or nil
                end
            else
                module.selectedBoss = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_BOSS, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_BOSS, nil)
            end
        end

        if Utils.isDebugEnabled() and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickBoss)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBoss)
                ))
        end

        -- If the focused boss changed, reset boss-attendees + loot selection (filters changed).
        if prevFocus ~= module.selectedBoss then
            module.selectedBossPlayer = nil
            Utils.multiSelectClear(MS_CTX_BOSSATT)

            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)

            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
            Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
        end

        Utils.triggerEvent("LoggerSelectBoss", module.selectedBoss)
    end

    -- Player filter: only one active at a time
    function module:SelectBossPlayer(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedBossPlayer

        -- Mutual exclusion: selecting a boss-attendee filter clears the raid-attendee filter (and its multi-select).
        module.selectedPlayer = nil
        Utils.multiSelectClear(MS_CTX_RAIDATT)

        local action, count
        if isRange then
            local ordered = addon.Logger.BossAttendees and addon.Logger.BossAttendees._ctrl and
                addon.Logger.BossAttendees._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_BOSSATT, ordered, id, isMulti)
            module.selectedBossPlayer = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_BOSSATT, id, isMulti, true)

            -- Keep a single "focused" boss-attendee for loot filtering.
            if action == "SINGLE_DESELECT" then
                module.selectedBossPlayer = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedBossPlayer == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_BOSSATT)
                    module.selectedBossPlayer = sel[1] or nil
                end
            else
                module.selectedBossPlayer = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_BOSSATT, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_BOSSATT, nil)
            end
        end

        if Utils.isDebugEnabled() and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickBossAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBossPlayer)
                ))
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedBossPlayer then
            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)
            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
        end

        Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
        Utils.triggerEvent("LoggerSelectPlayer", module.selectedPlayer)
    end

    function module:SelectPlayer(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedPlayer

        -- Mutual exclusion: selecting a raid-attendee filter clears the boss-attendee filter (and its multi-select).
        module.selectedBossPlayer = nil
        Utils.multiSelectClear(MS_CTX_BOSSATT)

        local action, count
        if isRange then
            local ordered = addon.Logger.RaidAttendees and addon.Logger.RaidAttendees._ctrl and
                addon.Logger.RaidAttendees._ctrl.data or nil
            action, count = Utils.multiSelectRange(MS_CTX_RAIDATT, ordered, id, isMulti)
            module.selectedPlayer = id
        else
            action, count = Utils.multiSelectToggle(MS_CTX_RAIDATT, id, isMulti, true)

            -- Keep a single "focused" raid-attendee for loot filtering.
            if action == "SINGLE_DESELECT" then
                module.selectedPlayer = nil
            elseif action == "TOGGLE_OFF" then
                if module.selectedPlayer == id then
                    local sel = Utils.multiSelectGetSelected(MS_CTX_RAIDATT)
                    module.selectedPlayer = sel[1] or nil
                end
            else
                module.selectedPlayer = id
            end

            if (tonumber(count) or 0) > 0 then
                Utils.multiSelectSetAnchor(MS_CTX_RAIDATT, id)
            else
                Utils.multiSelectSetAnchor(MS_CTX_RAIDATT, nil)
            end
        end

        if Utils.isDebugEnabled() and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickRaidAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedPlayer)
                ))
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedPlayer then
            module.selectedItem = nil
            Utils.multiSelectClear(MS_CTX_LOOT)
            Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
        end

        Utils.triggerEvent("LoggerSelectPlayer", module.selectedPlayer)
        Utils.triggerEvent("LoggerSelectBossPlayer", module.selectedBossPlayer)
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

        function module:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            -- NOTE: Multi-select is maintained in Utils.lua (context = MS_CTX_LOOT).
            if button == "LeftButton" then
                local isMulti = IsControlKeyDown and IsControlKeyDown() or false
                local isRange = IsShiftKeyDown and IsShiftKeyDown() or false

                local action, count
                if isRange then
                    local ordered = addon.Logger.Loot
                        and addon.Logger.Loot._ctrl
                        and addon.Logger.Loot._ctrl.data
                        or nil
                    action, count = Utils.multiSelectRange(MS_CTX_LOOT, ordered, id, isMulti)
                    module.selectedItem = id
                else
                    action, count = Utils.multiSelectToggle(MS_CTX_LOOT, id, isMulti, true)

                    -- Keep a single "focused" item for context menu / edit popups.
                    if action == "SINGLE_DESELECT" then
                        module.selectedItem = nil
                    elseif action == "TOGGLE_OFF" then
                        if module.selectedItem == id then
                            local sel = Utils.multiSelectGetSelected(MS_CTX_LOOT)
                            module.selectedItem = sel[1] or nil
                        end
                        -- If we toggled OFF a non-focused item, keep current focus.
                    else
                        module.selectedItem = id
                    end

                    if (tonumber(count) or 0) > 0 then
                        Utils.multiSelectSetAnchor(MS_CTX_LOOT, id)
                    else
                        Utils.multiSelectSetAnchor(MS_CTX_LOOT, nil)
                    end
                end

                if Utils.isDebugEnabled() and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickLoot)
                        :format(
                            tostring(id), isMulti and 1 or 0, isRange and 1 or 0,
                            tostring(action), tonumber(count) or 0,
                            tostring(module.selectedItem)
                        ))
                end

                Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
            elseif button == "RightButton" then
                -- Context menu works on a single focused row.
                local action, count = Utils.multiSelectToggle(MS_CTX_LOOT, id, false)
                module.selectedItem = id

                if Utils.isDebugEnabled() and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickContextMenu):format(
                        tostring(id), tostring(action), tonumber(count) or 0
                    ))
                end

                Utils.triggerEvent("LoggerSelectItem", module.selectedItem)
                openItemMenu()
            end
        end

        -- Hover sync: keep selection highlight persistent while hover uses default Button behavior.
        function module:OnLootRowEnter(row)
            -- No-op: persistent selection is rendered via overlay textures (Utils.setRowSelected/Focused).
            -- Leave native hover highlight behavior intact.
        end

        function module:OnLootRowLeave(row)
            -- No-op: persistent selection is rendered via overlay textures.
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
                local raid = Store:GetRaid(self.raidId)
                if not raid then
                    addon:error(L.ErrLoggerInvalidRaid)
                    return
                end

                local loot = Store:GetLoot(raid, self.itemId)
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

-- Raids List
do
    addon.Logger.Raids = addon.Logger.Raids or {}
    local Raids = addon.Logger.Raids
    local controller = Utils.makeListController {
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
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
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
                it.difficulty = tonumber(r.difficulty)
                local mode = it.difficulty and ((it.difficulty == 3 or it.difficulty == 4) and "H" or "N") or "?"
                it.sizeLabel = tostring(it.size or "") .. mode
                it.date = r.startTime
                it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                out[i] = it
            end
        end,

        rowName = function(n, _, i) return n .. "RaidBtn" .. i end,
        rowTmpl = "KRTLoggerRaidButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.ID:SetText(it.seq or it.id)
            ui.Date:SetText(it.dateFmt)
            ui.Zone:SetText(it.zone)
            ui.Size:SetText(it.sizeLabel or it.size)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msRaidCtx, id) end,
        focusId = function() return addon.Logger.selectedRaid end,
        focusKey = function() return tostring(addon.Logger.selectedRaid or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msRaidCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msRaidCtx),
                Utils.multiSelectCount(addon.Logger._msRaidCtx))
        end,

        postUpdate = function(n)
            local sel = addon.Logger.selectedRaid
            local raid = sel and KRT_Raids[sel] or nil

            local canSetCurrent = false
            if sel and raid and sel ~= KRT_CurrentRaid then
                -- This button is intended to resolve duplicate raid creation while actively raiding.
                if not addon.IsInRaid() then
                    canSetCurrent = false
                elseif addon.Raid:Expired(sel) then
                    canSetCurrent = false
                else
                    local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
                    if isDyn then
                        instanceDiff = instanceDiff + (2 * dynDiff)
                    end
                    if instanceType == "raid" then
                        local raidSize = tonumber(raid.size)
                        local groupSize = addon.Raid:GetRaidSize()
                        local zoneOk = (not raid.zone) or (raid.zone == instanceName)
                        local raidDiff = tonumber(raid.difficulty)
                        local curDiff = tonumber(instanceDiff)
                        local diffOk = raidDiff and curDiff and (raidDiff == curDiff)
                        canSetCurrent = zoneOk and raidSize and (raidSize == groupSize) and diffOk
                    end
                end
            end

            Utils.enableDisable(_G[n .. "CurrentBtn"], canSetCurrent)

            local ctx = addon.Logger._msRaidCtx
            local selCount = Utils.multiSelectCount(ctx)
            local canDelete = (selCount and selCount > 0) or false
            if canDelete and KRT_CurrentRaid then
                local ids = Utils.multiSelectGetSelected(ctx)
                for i = 1, #ids do
                    if tonumber(ids[i]) == tonumber(KRT_CurrentRaid) then
                        canDelete = false
                        break
                    end
                end
            end
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, selCount)
            Utils.enableDisable(delBtn, canDelete)
        end,

        sorters = {
            id = function(a, b, asc)
                return asc and ((a.seq or a.id) < (b.seq or b.id)) or
                    ((a.seq or a.id) > (b.seq or b.id))
            end,
            date = function(a, b, asc) return asc and (a.date < b.date) or (a.date > b.date) end,
            zone = function(a, b, asc) return asc and (a.zone < b.zone) or (a.zone > b.zone) end,
            size = function(a, b, asc) return asc and (a.size < b.size) or (a.size > b.size) end,
        },
    }

    Raids._ctrl = controller
    Utils.bindListController(Raids, controller)

    function Raids:SetCurrent(btn)
        if not btn then return end
        local sel = addon.Logger.selectedRaid
        if not sel then return end
        if addon.Logger.Actions:SetCurrentRaid(sel) then
            -- Context change: clear dependent selections and redraw all module panels.
            addon.Logger.selectedRaid = sel
            addon.Logger:ResetSelections()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end
    end

    do
        local function DeleteRaids()
            local ctx = addon.Logger._msRaidCtx
            local ids = Utils.multiSelectGetSelected(ctx)
            if not (ids and #ids > 0) then return end

            -- Safety: never delete the current raid
            if KRT_CurrentRaid then
                for i = 1, #ids do
                    if tonumber(ids[i]) == tonumber(KRT_CurrentRaid) then
                        return
                    end
                end
            end

            -- Deleting by index: sort descending to avoid shifting issues.
            table.sort(ids, function(a, b) return (tonumber(a) or a) > (tonumber(b) or b) end)

            local prevFocus = addon.Logger.selectedRaid
            local removed = 0
            for i = 1, #ids do
                if addon.Logger.Actions:DeleteRaid(ids[i]) then
                    removed = removed + 1
                end
            end

            Utils.multiSelectClear(ctx)

            local n = KRT_Raids and #KRT_Raids or 0
            local newFocus = nil
            if n > 0 then
                local base = tonumber(prevFocus) or n
                if base > n then base = n end
                if base < 1 then base = 1 end
                newFocus = base
            end

            addon.Logger.selectedRaid = newFocus
            addon.Logger:ResetSelections()
            controller:Dirty()
            Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
        end

        function Raids:Delete(btn)
            local ctx = addon.Logger._msRaidCtx
            if btn and Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaids)
    end

    Utils.registerCallback("RaidCreate", function(_, num)
        -- Context change: selecting a different raid must clear dependent selections.
        addon.Logger.selectedRaid = tonumber(num)
        addon.Logger:ResetSelections()
        controller:Dirty()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end)

    Utils.registerCallback("LoggerSelectRaid", function() controller:Touch() end)
end

-- Boss List
do
    addon.Logger.Boss = addon.Logger.Boss or {}
    local Boss = addon.Logger.Boss
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
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
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end
            View:FillBossList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "BossBtn" .. i end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            -- Display a sequential number that rescales after deletions.
            -- Keep it.id as the stable bossNid for selection/highlight.
            ui.ID:SetText(it.seq)
            ui.Name:SetText(it.name)
            ui.Time:SetText(it.timeFmt)
            ui.Mode:SetText(it.mode)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msBossCtx, id) end,
        focusId = function() return addon.Logger.selectedBoss end,
        focusKey = function() return tostring(addon.Logger.selectedBoss or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msBossCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msBossCtx),
                Utils.multiSelectCount(addon.Logger._msBossCtx))
        end,

        postUpdate = function(n)
            local hasRaid = addon.Logger.selectedRaid
            local hasBoss = addon.Logger.selectedBoss
            Utils.enableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            Utils.enableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            local bossSelCount = Utils.multiSelectCount(addon.Logger._msBossCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, bossSelCount)
            Utils.enableDisable(delBtn, (bossSelCount and bossSelCount > 0) or false)
        end,

        sorters = {
            -- Sort by the displayed sequential number, not the stable nid.
            id = function(a, b, asc) return asc and (a.seq < b.seq) or (a.seq > b.seq) end,
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
            time = function(a, b, asc) return asc and (a.time < b.time) or (a.time > b.time) end,
            mode = function(a, b, asc) return asc and (a.mode < b.mode) or (a.mode > b.mode) end,
        },
    }

    Boss._ctrl = controller
    Utils.bindListController(Boss, controller)

    function Boss:Add() addon.Logger.BossBox:Toggle() end

    function Boss:Edit() if addon.Logger.selectedBoss then addon.Logger.BossBox:Fill() end end

    do
        local function DeleteBosses()
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msBossCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

                for i = 1, #ids do
                    local bNid = ids[i]
                    local lootRemoved = Actions:DeleteBoss(rID, bNid)
                    addon:debug(Diag.D.LogLoggerBossLootRemoved, rID, tonumber(bNid) or -1, lootRemoved)
                end

                -- Clear boss-related selections (filters changed / deleted)
                Utils.multiSelectClear(ctx)
                addon.Logger.selectedBoss = nil

                addon.Logger.selectedBossPlayer = nil
                Utils.multiSelectClear(addon.Logger._msBossAttCtx)

                addon.Logger.selectedItem = nil
                Utils.multiSelectClear(addon.Logger._msLootCtx)
            end)
        end

        function Boss:Delete()
            local ctx = addon.Logger._msBossCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBosses)
    end

    function Boss:GetName(bossNid, raidId)
        local rID = raidId or addon.Logger.selectedRaid
        if not rID or not KRT_Raids[rID] then return "" end
        bossNid = bossNid or addon.Logger.selectedBoss
        if not bossNid then return "" end

        local raid = Store:GetRaid(rID)
        local boss = raid and Store:GetBoss(raid, bossNid) or nil
        return boss and boss.name or ""
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBoss", function() controller:Touch() end)
end

-- Boss Attendees List
do
    addon.Logger.BossAttendees = addon.Logger.BossAttendees or {}
    local BossAtt = addon.Logger.BossAttendees
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBossAttendees) end
            local add = _G[n .. "AddBtn"]; if add then add:SetText(L.BtnAdd) end
            local rm = _G[n .. "RemoveBtn"]; if rm then rm:SetText(L.BtnRemove) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
        end,

        getData = function(out)
            local rID = addon.Logger.selectedRaid
            local bID = addon.Logger.selectedBoss
            local raid = (rID and bID) and Store:GetRaid(rID) or nil
            if not (raid and bID) then return end
            View:FillBossAttendeesList(out, raid, bID)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            local r, g, b = Utils.getClassColor(it.class)
            ui.Name:SetText(it.name)
            ui.Name:SetVertexColor(r, g, b)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msBossAttCtx, id) end,
        focusId = function() return addon.Logger.selectedBossPlayer end,
        focusKey = function() return tostring(addon.Logger.selectedBossPlayer or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msBossAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msBossAttCtx),
                Utils.multiSelectCount(addon.Logger._msBossAttCtx))
        end,

        postUpdate = function(n)
            local bSel = addon.Logger.selectedBoss
            local pSel = addon.Logger.selectedBossPlayer
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = Utils.multiSelectCount(addon.Logger._msBossAttCtx)
            if addBtn then
                Utils.enableDisable(addBtn, bSel and ((attSelCount or 0) == 0))
            end
            if removeBtn then
                Utils.setButtonCount(removeBtn, L.BtnRemove, attSelCount)
                Utils.enableDisable(removeBtn, bSel and ((attSelCount or 0) > 0))
            end
        end,

        sorters = {
            name = function(a, b, asc) return asc and (a.name < b.name) or (a.name > b.name) end,
        },
    }

    BossAtt._ctrl = controller
    Utils.bindListController(BossAtt, controller)

    function BossAtt:Add() addon.Logger.AttendeesBox:Toggle() end

    do
        local function DeleteAttendees()
            addon.Logger:Run(function(_, rID)
                local bNid = addon.Logger.selectedBoss
                local ctx = addon.Logger._msBossAttCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (bNid and ids and #ids > 0) then return end

                for i = 1, #ids do
                    Actions:DeleteBossAttendee(rID, bNid, ids[i])
                end

                Utils.multiSelectClear(ctx)
                addon.Logger.selectedBossPlayer = nil
            end)
        end

        function BossAtt:Delete()
            local ctx = addon.Logger._msBossAttCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
    end

    Utils.registerCallbacks({ "LoggerSelectRaid", "LoggerSelectBoss" }, function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectBossPlayer", function() controller:Touch() end)
end

-- Raid Attendees List
do
    addon.Logger.RaidAttendees = addon.Logger.RaidAttendees or {}
    local RaidAtt = addon.Logger.RaidAttendees
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidAttendees) end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                addBtn:SetText(L.BtnUpdate)
                local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
                addBtn:Disable() -- enabled in postUpdate when applicable
            end
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end
            View:FillRaidAttendeesList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            ui.Name:SetText(it.name)
            local r, g, b = Utils.getClassColor(it.class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Join:SetText(it.joinFmt)
            ui.Leave:SetText(it.leaveFmt)
        end),

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msRaidAttCtx, id) end,
        focusId = function() return addon.Logger.selectedPlayer end,
        focusKey = function() return tostring(addon.Logger.selectedPlayer or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msRaidAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msRaidAttCtx),
                Utils.multiSelectCount(addon.Logger._msRaidAttCtx))
        end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            if deleteBtn then
                local attSelCount = Utils.multiSelectCount(addon.Logger._msRaidAttCtx)
                Utils.setButtonCount(deleteBtn, L.BtnDelete, attSelCount)
                Utils.enableDisable(deleteBtn, (attSelCount and attSelCount > 0) or false)
            end

            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                -- Update is only meaningful for the current raid session while actively raiding.
                local can = addon.IsInRaid() and KRT_CurrentRaid and addon.Logger.selectedRaid
                    and (tonumber(KRT_CurrentRaid) == tonumber(addon.Logger.selectedRaid))
                Utils.enableDisable(addBtn, can)
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

    RaidAtt._ctrl = controller
    Utils.bindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function RaidAtt:Add()
        addon.Logger:Run(function(_, rID)
            local sel = tonumber(rID)
            if not sel then return end

            if not addon.IsInRaid() then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotInRaid)
                return
            end

            if not (KRT_CurrentRaid and tonumber(KRT_CurrentRaid) == sel) then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotCurrent)
                return
            end

            -- Update the roster from the live in-game raid roster.
            addon.Raid:UpdateRaidRoster()

            -- Clear selections that depend on raid.players indices.
            Utils.multiSelectClear(addon.Logger._msRaidAttCtx)
            Utils.multiSelectClear(addon.Logger._msBossAttCtx)
            Utils.multiSelectClear(addon.Logger._msLootCtx)
            addon.Logger.selectedPlayer = nil
            addon.Logger.selectedBossPlayer = nil
            addon.Logger.selectedItem = nil

            controller:Dirty()
        end)
    end

    do
        local function DeleteAttendees()
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msRaidAttCtx
                local ids = Utils.multiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

                local removed = Actions:DeleteRaidAttendeeMany(rID, ids)
                if removed and removed > 0 then
                    Utils.multiSelectClear(ctx)
                    addon.Logger.selectedPlayer = nil

                    -- Indices shifted: clear boss-attendees selection too (it is indexed by raid.players).
                    addon.Logger.selectedBossPlayer = nil
                    Utils.multiSelectClear(addon.Logger._msBossAttCtx)

                    -- Filters changed: reset loot selection.
                    addon.Logger.selectedItem = nil
                    Utils.multiSelectClear(addon.Logger._msLootCtx)
                end
            end)
        end

        function RaidAtt:Delete()
            local ctx = addon.Logger._msRaidAttCtx
            if Utils.multiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
    end

    Utils.registerCallback("LoggerSelectRaid", function() controller:Dirty() end)
    Utils.registerCallback("LoggerSelectPlayer", function() controller:Touch() end)
end

-- Loot List (filters by selected boss and player)
do
    addon.Logger.Loot = addon.Logger.Loot or {}
    local Loot = addon.Logger.Loot
    local Store = addon.Logger.Store
    local View = addon.Logger.View
    local Actions = addon.Logger.Actions

    local controller = Utils.makeListController {
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrRaidLoot) end
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
            local del = _G[n .. "DeleteBtn"]; if del then del:SetText(L.BtnDelete) end
            _G[n .. "EditBtn"]:Disable()
        end,

        getData = function(out)
            local raid = addon.Logger:NeedRaid()
            if not raid then return end

            local bID = addon.Logger.selectedBoss
            local pID = addon.Logger.selectedBossPlayer or addon.Logger.selectedPlayer
            local pName = (pID and raid.players and raid.players[pID] and raid.players[pID].name) or nil

            View:FillLootList(out, raid, bID, pName)
        end,

        rowName = function(n, _, i) return n .. "ItemBtn" .. i end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = Utils.createRowDrawer(function(row, it)
            local ui = row._p
            -- Preserve the original item link on the row for tooltips.
            row._itemLink = it.itemLink
            local nameText = it.itemLink or it.itemName or ("[Item " .. (it.itemId or "?") .. "]")
            if it.itemLink then
                ui.Name:SetText(nameText)
            else
                ui.Name:SetText(addon.WrapTextInColorCode(
                    nameText,
                    Utils.normalizeHexColor(itemColors[(it.itemRarity or 1) + 1])
                ))
            end

            local selectedBoss = addon.Logger.selectedBoss
            if selectedBoss and tonumber(it.bossNid) == tonumber(selectedBoss) then
                ui.Source:SetText("")
            else
                ui.Source:SetText(addon.Logger.Boss:GetName(it.bossNid, addon.Logger.selectedRaid))
            end

            local r, g, b = Utils.getClassColor(addon.Raid:GetPlayerClass(it.looter))
            ui.Winner:SetText(it.looter)
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

        highlightFn = function(id) return Utils.multiSelectIsSelected(addon.Logger._msLootCtx, id) end,
        focusId = function() return addon.Logger.selectedItem end,
        focusKey = function() return tostring(addon.Logger.selectedItem or "nil") end,
        highlightKey = function() return Utils.multiSelectGetVersion(addon.Logger._msLootCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(addon.Logger._msLootCtx),
                Utils.multiSelectCount(addon.Logger._msLootCtx))
        end,

        postUpdate = function(n)
            local lootSelCount = Utils.multiSelectCount(addon.Logger._msLootCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            Utils.setButtonCount(delBtn, L.BtnDelete, lootSelCount)
            Utils.enableDisable(delBtn, (lootSelCount or 0) > 0)
        end,

        sorters = {
            id = function(a, b, asc) return asc and (a.itemId < b.itemId) or (a.itemId > b.itemId) end,
            source = function(a, b, asc)
                return asc and ((tonumber(a.bossNid) or 0) < (tonumber(b.bossNid) or 0)) or
                    ((tonumber(a.bossNid) or 0) > (tonumber(b.bossNid) or 0))
            end,
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

    Loot._ctrl = controller
    Utils.bindListController(Loot, controller)

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
            addon.Logger:Run(function(_, rID)
                local ctx = addon.Logger._msLootCtx
                local selected = Utils.multiSelectGetSelected(ctx)
                if not selected or #selected == 0 then return end

                local removed = Actions:DeleteLootMany(rID, selected)
                if removed > 0 then
                    Utils.multiSelectClear(ctx)
                    addon.Logger.selectedItem = nil
                    Utils.triggerEvent("LoggerSelectItem", addon.Logger.selectedItem)

                    if Utils.isDebugEnabled() and addon.debug then
                        addon:debug((Diag.D.LogLoggerSelectDeleteItems):format(removed))
                    end
                end
            end)
        end

        function Loot:Delete()
            if Utils.multiSelectCount(addon.Logger._msLootCtx) > 0 then
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
            -- If the module window is open and browsing an old raid, selectedRaid may differ from KRT_CurrentRaid.
            -- Runtime sources must always write into the CURRENT raid session.
            -- Logger UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = addon.Logger.selectedRaid or KRT_CurrentRaid
            else
                raidID = KRT_CurrentRaid or addon.Logger.selectedRaid
            end
        end
        addon:trace(Diag.D.LogLoggerLootLogAttempt:format(tostring(source), tostring(raidID), tostring(itemID),
            tostring(looter), tostring(rollType), tostring(rollValue), tostring(KRT_LastBoss)))
        if not raidID or not KRT_Raids[raidID] then
            addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(itemID)))
            return false
        end

        local raid = KRT_Raids[raidID]
        Store:EnsureRaid(raid)
        local lootCount = raid.loot and #raid.loot or 0
        local it = Store:GetLoot(raid, itemID)
        if not it then
            addon:error(Diag.E.LogLoggerItemNotFound:format(raidID, tostring(itemID), lootCount))
            return false
        end

        if not looter or looter == "" then
            addon:warn(Diag.W.LogLoggerLooterEmpty:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        if rollType == nil then
            addon:warn(Diag.W.LogLoggerRollTypeNil:format(raidID, tostring(itemID), tostring(looter)))
        end

        addon:debug(Diag.D.LogLoggerLootBefore:format(raidID, tostring(itemID), tostring(it.itemLink),
            tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))
        if it.looter and it.looter ~= "" and looter and looter ~= "" and it.looter ~= looter then
            addon:warn(Diag.W.LogLoggerLootOverwrite:format(raidID, tostring(itemID), tostring(it.itemLink),
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
        addon:debug(Diag.D.LogLoggerLootRecorded:format(tostring(source), raidID, tostring(itemID),
            tostring(it.itemLink), tostring(it.looter), tostring(it.rollType), tostring(it.rollValue)))

        local ok = true
        if expectedLooter and it.looter ~= expectedLooter then ok = false end
        if expectedRollType and it.rollType ~= expectedRollType then ok = false end
        if expectedRollValue and it.rollValue ~= expectedRollValue then ok = false end
        if not ok then
            addon:error(Diag.E.LogLoggerVerifyFailed:format(raidID, tostring(itemID), tostring(it.looter),
                tostring(it.rollType), tostring(it.rollValue)))
            return false
        end

        addon:debug(Diag.D.LogLoggerVerified:format(raidID, tostring(itemID)))
        if not KRT_LastBoss then
            addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(itemID), tostring(it.itemLink)))
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

-- module: Add/Edit Boss Popup  (Patch #1 - normalize to time/mode)
do
    addon.Logger.BossBox = addon.Logger.BossBox or {}
    local Box = addon.Logger.BossBox
    local Store = addon.Logger.Store

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local getFrame = Utils.makeFrameGetter("KRTLoggerBossBox")

    function Box:OnLoad(frame)
        frameName = Utils.initModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = function()
                Box:UpdateUIFrame()
            end,
            hookOnHide = function()
                Box:CancelAddEdit()
            end,
        })
        if not frameName then return end

        local nameStr = _G[frameName .. "NameStr"]
        if nameStr then
            nameStr:SetText(L.StrName)
        end
        local diffStr = _G[frameName .. "DifficultyStr"]
        if diffStr then
            diffStr:SetText(L.StrDifficulty)
        end
        local timeStr = _G[frameName .. "TimeStr"]
        if timeStr then
            timeStr:SetText(L.StrTime)
        end
        local saveBtn = _G[frameName .. "SaveBtn"]
        if saveBtn then
            saveBtn:SetText(L.BtnSave)
        end
        local cancelBtn = _G[frameName .. "CancelBtn"]
        if cancelBtn then
            cancelBtn:SetText(L.BtnCancel)
        end
    end

    local uiController = Utils.bootstrapModuleUi(Box, getFrame, function()
        Box:UpdateUIFrame()
    end)

    function Box:Toggle() return uiController:Toggle() end

    function Box:Hide() return uiController:Hide() end

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        if not (rID and bID) then return end

        raidData = Store:GetRaid(rID)
        if not raidData then return end

        bossData = Store:GetBoss(raidData, bID)
        if not bossData then return end

        _G[frameName .. "Name"]:SetText(bossData.name or "")

        local bossTime = bossData.time or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        _G[frameName .. "Time"]:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        _G[frameName .. "Difficulty"]:SetText((mode == "h") and "h" or "n")

        editBossNid = bossData and bossData.bossNid or nil
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

        local bossNid = isEdit and editBossNid or nil
        local savedNid = addon.Logger.Actions:UpsertBossKill(rID, bossNid, name, time(killDate), mode)
        if not savedNid then return end

        self:Hide()
        addon.Logger:ResetSelections()
        Utils.triggerEvent("LoggerSelectRaid", addon.Logger.selectedRaid)
    end

    function Box:CancelAddEdit()
        Utils.resetEditBox(_G[frameName .. "Name"])
        Utils.resetEditBox(_G[frameName .. "Difficulty"])
        Utils.resetEditBox(_G[frameName .. "Time"])
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    function Box:UpdateUIFrame()
        if not localized then
            addon:SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            addon:SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        Utils.setText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
    end
end

-- module: Add Attendee Popup
do
    addon.Logger.AttendeesBox = addon.Logger.AttendeesBox or {}
    local Box = addon.Logger.AttendeesBox
    local Store = addon.Logger.Store

    local frameName
    local getFrame = Utils.makeFrameGetter("KRTLoggerAttendeesBox")

    function Box:OnLoad(frame)
        frameName = Utils.initModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = function()
                Utils.resetEditBox(_G[frameName .. "Name"])
            end,
            hookOnHide = function()
                Utils.resetEditBox(_G[frameName .. "Name"])
            end,
        })
        if not frameName then return end

        local title = _G[frameName .. "Title"]
        if title then
            title:SetText(L.StrAddPlayer)
        end
        local nameStr = _G[frameName .. "NameStr"]
        if nameStr then
            nameStr:SetText(L.StrName)
        end
        local addBtn = _G[frameName .. "AddBtn"]
        if addBtn then
            addBtn:SetText(L.BtnAdd)
        end
        local cancelBtn = _G[frameName .. "CancelBtn"]
        if cancelBtn then
            cancelBtn:SetText(L.BtnCancel)
        end
    end

    local uiController = Utils.bootstrapModuleUi(Box, getFrame)

    function Box:Toggle() return uiController:Toggle() end

    function Box:Save()
        local rID, bID = addon.Logger.selectedRaid, addon.Logger.selectedBoss
        local name = Utils.trimText(_G[frameName .. "Name"]:GetText())
        if addon.Logger.Actions:AddBossAttendee(rID, bID, name) then
            self:Toggle()
            Utils.triggerEvent("LoggerSelectBoss", addon.Logger.selectedBoss)
        end
    end
end
