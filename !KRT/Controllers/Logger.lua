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
local Frames = feature.Frames or addon.Frames
local Strings = feature.Strings or addon.Strings
local Colors = feature.Colors or addon.Colors
local Base64 = feature.Base64 or addon.Base64
local Sort = feature.Sort or addon.Sort

local CompareValues = Sort.CompareValues
local CompareNumbers = Sort.CompareNumbers
local CompareStrings = Sort.CompareStrings
local GetLootSortName = Sort.GetLootSortName
local CompareLootTie = Sort.CompareLootTie

local InternalEvents = Events.Internal

local bindModuleRequestRefresh = feature.BindModuleRequestRefresh
local bindModuleToggleHide = feature.BindModuleToggleHide
local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local rollTypes = feature.rollTypes
local lootTypesColored = feature.lootTypesColored
local itemColors = feature.itemColors

local _G = _G
local tinsert, tremove, twipe = table.insert, table.remove, table.wipe
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber
local strlower = string.lower

local SetSelectedRaid

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

-- Logger frame module.
do
    addon.Controllers = addon.Controllers or {}
    addon.Controllers.Logger = addon.Controllers.Logger or {}
    local module   = addon.Controllers.Logger

    -- ----- Internal state ----- --
    local frameName
    local getFrame = makeModuleFrameGetter(module, "KRTLogger")
    local uiBound = false
    local scaffoldToggle, scaffoldHide
    -- Stable-ID data helpers (fresh SavedVariables only; no legacy migration).
    module.Store   = module.Store or {}
    module.View    = module.View or {}
    module.Actions = module.Actions or {}

    local Store    = module.Store
    local View     = module.View
    local Actions  = module.Actions

    -- ----- Private helpers ----- --
    local function AcquireRefs(frame)
        return {
            raids = Frames.Ref(frame, "Raids"),
            bosses = Frames.Ref(frame, "Bosses"),
            loot = Frames.Ref(frame, "Loot"),
            raidAttendees = Frames.Ref(frame, "RaidAttendees"),
            bossAttendees = Frames.Ref(frame, "BossAttendees"),
            bossBox = Frames.Get("KRTLoggerBossBox"),
            attendeesBox = Frames.Ref(frame, "PlayerBox"),
        }
    end

    local function EnsureSubmoduleOnLoad(moduleRef, frame)
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

        local action, count = MultiSelect.MultiSelectToggle(ctx, id, opts.isMulti, true)
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

    local function normalizeNid(v)
        return tonumber(v) or v
    end

    local function buildIndex(raid, listField, idField, cacheField)
        local list = raid[listField]
        if type(list) ~= "table" then
            list = {}
        end
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

    local function isIndexedMatch(raid, idx, listField, idField, normalizedNid)
        if not idx then return false end
        local list = raid[listField]
        if type(list) ~= "table" then return false end
        local e = list[idx]
        if not e then return false end
        local id = e[idField]
        if id == nil then return false end
        return normalizeNid(id) == normalizedNid
    end

    local function getIndexedPositionByNid(raid, queryNid, listField, idField, cacheField)
        if not (raid and queryNid) then return nil end

        local normalizedNid = normalizeNid(queryNid)
        if type(raid[cacheField]) ~= "table" then
            buildIndex(raid, listField, idField, cacheField)
        end

        local idx = raid[cacheField][normalizedNid]
        if not isIndexedMatch(raid, idx, listField, idField, normalizedNid) then
            -- Raid changed since last build (new entry added / list changed / shifted indices)
            buildIndex(raid, listField, idField, cacheField)
            idx = raid[cacheField][normalizedNid]
            if not isIndexedMatch(raid, idx, listField, idField, normalizedNid) then
                return nil
            end
        end
        return idx
    end

    -- ----- Public methods ----- --
    -- Ensure the raid table follows the canonical fresh-SV schema.
    function Store:EnsureRaid(raid)
        return Core.EnsureRaidSchema(raid)
    end

    function Store:GetRaid(rID)
        local raid = rID and Core.EnsureRaidById(rID) or nil
        if raid then
            self:EnsureRaid(raid)
        end
        return raid
    end

    function Store:GetRaidByNid(raidNid)
        local raid = raidNid and Core.EnsureRaidByNid(raidNid) or nil
        if raid then
            self:EnsureRaid(raid)
        end
        return raid
    end

    function Store:InvalidateIndexes(raid)
        if not raid then return end
        raid._bossIdxByNid = nil
        raid._lootIdxByNid = nil
        raid._playerIdxByNid = nil
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

    function Store:PlayerIdx(raid, playerNid)
        return getIndexedPositionByNid(raid, playerNid, "players", "playerNid", "_playerIdxByNid")
    end

    function Store:GetPlayer(raid, playerNid)
        local idx = self:PlayerIdx(raid, playerNid)
        return idx and raid.players[idx] or nil, idx
    end

    function Store:FindRaidPlayerByNormName(raid, normalizedLower)
        if not (raid and normalizedLower) then return nil end
        local players = raid.players or {}
        for i = 1, #players do
            local p = players[i]
            if p and p.name and Strings.NormalizeLower(p.name) == normalizedLower then
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
            it.id = tonumber(boss and boss.bossNid)
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
            it.id = tonumber(p and p.playerNid)
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
                it.id = tonumber(p.playerNid)
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
                it.sortName = GetLootSortName(v.itemName, v.itemLink, v.itemId)
                local boss = Store:GetBoss(raid, v.bossNid)
                it.sourceName = (boss and boss.name) or ""
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

        -- Rebuild canonical raid schema/runtime indexes after in-place mutations.
        Core.EnsureRaidSchema(raid)

        if opts.invalidate ~= false then
            Store:InvalidateIndexes(raid)
        end

        local log = module
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

        -- Validate player selections (playerNid).
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
            if log.selectedPlayer and not Store:GetPlayer(raid, log.selectedPlayer) then
                log.selectedPlayer = nil
                changedPlayer = true
            end
            if log.selectedBossPlayer and not Store:GetPlayer(raid, log.selectedBossPlayer) then
                log.selectedBossPlayer = nil
                changedBossPlayer = true
            end
        end

        if changedBoss then triggerSelectionEvent(log, "selectedBoss") end
        if changedPlayer then triggerSelectionEvent(log, "selectedPlayer") end
        if changedBossPlayer then triggerSelectionEvent(log, "selectedBossPlayer") end
        if changedItem then triggerSelectionEvent(log, "selectedItem") end
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

        if Core.GetCurrentRaid() == rID and tonumber(Core.GetLastBoss()) == tonumber(bossNid) then
            Core.SetLastBoss(nil)
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

    function Actions:DeleteBossAttendee(rID, bossNid, playerNid)
        local raid = Store:GetRaid(rID)
        if not (raid and bossNid and playerNid) then return false end
        local bossKill = Store:GetBoss(raid, bossNid)
        if not (bossKill and bossKill.players and raid.players) then return false end
        local player = Store:GetPlayer(raid, playerNid)
        if not player then return false end
        local name = player.name
        if not name then return false end
        self:RemoveAll(bossKill.players, name)
        return true
    end

    function Actions:DeleteRaidAttendee(rID, playerNid)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and playerNid) then return false end

        local _, playerIdx = Store:GetPlayer(raid, playerNid)
        if not playerIdx then return false end
        local name = raid.players[playerIdx] and raid.players[playerIdx].name
        if not name then return false end

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

    -- Bulk delete: removes multiple raid attendees (by playerNid) with a single Commit()
    -- Returns: number of removed attendees
    function Actions:DeleteRaidAttendeeMany(rID, playerNids)
        local raid = Store:GetRaid(rID)
        if not (raid and raid.players and playerNids and #playerNids > 0) then return 0 end

        -- Normalize NIDs to indices, then sort descending (indices shift on removal).
        local ids = {}
        local seen = {}
        for i = 1, #playerNids do
            local nid = tonumber(playerNids[i]) or playerNids[i]
            if nid ~= nil then
                local _, idx = Store:GetPlayer(raid, nid)
                if idx and not seen[idx] then
                    seen[idx] = true
                    tinsert(ids, idx)
                end
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
        local raid = sel and Core.EnsureRaidById(sel) or nil
        if not raid then return false end

        if Core.GetCurrentRaid() and Core.GetCurrentRaid() == sel then
            addon:error(L.ErrCannotDeleteRaid)
            return false
        end

        tremove(KRT_Raids, sel)

        if Core.GetCurrentRaid() and Core.GetCurrentRaid() > sel then
            Core.SetCurrentRaid(Core.GetCurrentRaid() - 1)
        end

        return true
    end

    function Actions:DeleteRaidByNid(raidNid)
        local nid = tonumber(raidNid)
        if not nid then return false end
        local raid, sel = Core.EnsureRaidByNid(nid)
        if not (raid and sel) then return false end

        local currentRaidNid = Core.GetRaidNidById(Core.GetCurrentRaid())
        if currentRaidNid and tonumber(currentRaidNid) == nid then
            addon:error(L.ErrCannotDeleteRaid)
            return false
        end

        tremove(KRT_Raids, sel)

        if Core.GetCurrentRaid() and Core.GetCurrentRaid() > sel then
            Core.SetCurrentRaid(Core.GetCurrentRaid() - 1)
        end

        return true
    end

    function Actions:SetCurrentRaid(rID)
        local sel = tonumber(rID)
        local raid = sel and Core.EnsureRaidById(sel) or nil
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

        Core.SetCurrentRaid(sel)
        Core.SetLastBoss(nil)

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

        name = Strings.TrimText(name or "")
        mode = Strings.NormalizeLower(mode or "n")
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
            hash = Base64.Encode(rID .. "|" .. name .. "|" .. newNid),
        })

        self:Commit(raid)
        return newNid
    end

    -- Add existing raid player to the selected boss attendees list.
    -- nameRaw is matched (case-insensitive) against raid.players[].name.
    function Actions:AddBossAttendee(rID, bossNid, nameRaw)
        local name = Strings.TrimText(nameRaw or "")
        local normalizedName = Strings.NormalizeLower(name)
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
            if Strings.NormalizeLower(n) == normalizedName then
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

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        clearSelection(module, "selectedBoss", MS_CTX_BOSS)
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
        clearSelection(module, "selectedItem", MS_CTX_LOOT)
    end

    local rosterUiRefreshDebounceSeconds = 0.25

    local function isLoggerViewingCurrentRaid()
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

    local function requestRosterBoundListsRefresh()
        addon.CancelTimer(module._rosterUiHandle, true)
        module._rosterUiHandle = addon.NewTimer(rosterUiRefreshDebounceSeconds, function()
            module._rosterUiHandle = nil
            if not isLoggerViewingCurrentRaid() then
                return
            end
            refreshRosterBoundLists()
        end)
    end

    local function getRaidNidByIndex(raidIndex)
        return raidIndex and Core.GetRaidNidById(raidIndex) or nil
    end

    local function getRaidIndexByNid(raidNid)
        return raidNid and Core.GetRaidIdByNid(raidNid) or nil
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
            Bus.TriggerEvent(refreshEvent or InternalEvents.LoggerSelectRaid, module.selectedRaid)
        end
    end

    function module:ResetSelections()
        clearSelections()
    end

    function module:OnLoad(frame)
        frameName = Frames.InitModuleFrame(module, frame, {
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
        })
        if not frameName then return end
        Frames.SetFrameTitle(frameName, L.StrLootLogger)
    end

    -- Initialize UI controller for Toggle/Hide.
    UIScaffold.BootstrapModuleUi(module, getFrame, function() module:RequestRefresh() end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    scaffoldToggle = module.Toggle
    scaffoldHide = module.Hide

    function addon.Controllers.Logger:BindUI()
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

        EnsureSubmoduleOnLoad(module.Raids, refs.raids)
        EnsureSubmoduleOnLoad(module.Boss, refs.bosses)
        EnsureSubmoduleOnLoad(module.Loot, refs.loot)
        EnsureSubmoduleOnLoad(module.RaidAttendees, refs.raidAttendees)
        EnsureSubmoduleOnLoad(module.BossAttendees, refs.bossAttendees)
        EnsureSubmoduleOnLoad(module.BossBox, refs.bossBox)
        EnsureSubmoduleOnLoad(module.AttendeesBox, refs.attendeesBox)

        uiBound = true
        return frame, refs
    end

    function addon.Controllers.Logger:EnsureUI()
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

    function module:Refresh()
        local frame = getFrame()
        if not frame then return end
        if not module.selectedRaid then
            SetSelectedRaid(Core.GetCurrentRaid())
        end
        clearSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    -- Selectors
    function module:SelectRaid(btn, button)
        if button and button ~= "LeftButton" then return end
        local raidNid = btn and btn.GetID and btn:GetID()
        if not raidNid then return end
        local raidIndex = getRaidIndexByNid(raidNid)
        if not raidIndex then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedRaid

        local ordered = module.Raids and module.Raids._ctrl and module.Raids._ctrl.data or nil
        local action, count = applyFocusedMultiSelect({
            id = raidNid,
            context = MS_CTX_RAID,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            setFocus = SetSelectedRaid,
            mapSelectedToFocus = getRaidIndexByNid,
            isClickedFocused = function(clickedNid)
                return getRaidNidByIndex(module.selectedRaid) == clickedNid
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug((Diag.D.LogLoggerSelectClickRaid)
                :format(
                    tostring(raidNid), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedRaid)
                ))
        end

        -- If the focused raid changed, reset dependent selections (boss/player/loot panels).
        if prevFocus ~= module.selectedRaid then
            clearSelections()
        end

        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function module:SelectBoss(btn, button)
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
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
            addon:debug((Diag.D.LogLoggerSelectClickBoss)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBoss)
                ))
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
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedBossPlayer

        -- Mutual exclusion: selecting a boss-attendee filter clears the raid-attendee filter (and its multi-select).
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)

        local ordered = module.BossAttendees and module.BossAttendees._ctrl and
            module.BossAttendees._ctrl.data or nil
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
            addon:debug((Diag.D.LogLoggerSelectClickBossAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedBossPlayer)
                ))
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
        if button and button ~= "LeftButton" then return end
        local id = btn and btn.GetID and btn:GetID()
        if not id then return end

        local isMulti = (IsControlKeyDown and IsControlKeyDown()) or false
        local isRange = (IsShiftKeyDown and IsShiftKeyDown()) or false
        local prevFocus = module.selectedPlayer

        -- Mutual exclusion: selecting a raid-attendee filter clears the boss-attendee filter (and its multi-select).
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)

        local ordered = module.RaidAttendees and module.RaidAttendees._ctrl and
            module.RaidAttendees._ctrl.data or nil
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
            addon:debug((Diag.D.LogLoggerSelectClickRaidAttendees)
                :format(
                    tostring(id), isMulti and 1 or 0, isRange and 1 or 0, tostring(action), tonumber(count) or 0,
                    tostring(module.selectedPlayer)
                ))
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
            { rollType = rollTypes.MAINSPEC,   label = L.BtnMS,         suffix = "MS" },
            { rollType = rollTypes.OFFSPEC,    label = L.BtnOS,         suffix = "OS" },
            { rollType = rollTypes.RESERVED,   label = L.BtnSR,         suffix = "SR" },
            { rollType = rollTypes.FREE,       label = L.BtnFree,       suffix = "Free" },
            { rollType = rollTypes.BANK,       label = L.BtnBank,       suffix = "Bank" },
            { rollType = rollTypes.DISENCHANT, label = L.BtnDisenchant, suffix = "DE" },
            { rollType = rollTypes.HOLD,       label = L.BtnHold,       suffix = "Hold" },
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

        local function applySelectedItemRollType(itemId, rollType)
            if not itemId then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end
            module.Loot:Log(itemId, nil, rollType, nil, "LOGGER_EDIT_ROLLTYPE")
        end

        local function getItemMenuFrame()
            return _G.KRTLoggerItemMenuFrame
                or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
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
                        applySelectedItemRollType(parent and parent.itemId, rollType)
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
                            if not base then return end
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

                    picker.itemId = itemId
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
                        picker.itemId = nil
                        picker:Hide()
                        picker:SetParent(UIParent)
                    end
                end,
            }
            return true
        end

        local function openItemRollTypePopup()
            local itemId = module.selectedItem
            if not itemId then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end

            if not ensureRollTypePopup() then
                return
            end

            CloseDropDownMenus()
            StaticPopup_Show(ROLLTYPE_POPUP_KEY, nil, nil, {
                itemId = itemId,
            })
        end

        local function openItemMenu()
            local f = getItemMenuFrame()

            EasyMenu({
                {
                    text = L.StrEditItemLooter,
                    notCheckable = 1,
                    func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER") end,
                },
                {
                    text = L.StrEditItemRollType,
                    notCheckable = 1,
                    func = openItemRollTypePopup,
                },
                {
                    text = L.StrEditItemRollValue,
                    notCheckable = 1,
                    func = function() StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE") end,
                },
            }, f, "cursor", 0, 0, "MENU")
        end

        function module:SelectItem(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then return end

            -- NOTE: Multi-select is maintained in MultiSelect module (context = MS_CTX_LOOT).
            if button == "LeftButton" then
                local isMulti = IsControlKeyDown and IsControlKeyDown() or false
                local isRange = IsShiftKeyDown and IsShiftKeyDown() or false

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
                    addon:debug((Diag.D.LogLoggerSelectClickLoot)
                        :format(
                            tostring(id), isMulti and 1 or 0, isRange and 1 or 0,
                            tostring(action), tonumber(count) or 0,
                            tostring(module.selectedItem)
                        ))
                end

                triggerSelectionEvent(module, "selectedItem")
            elseif button == "RightButton" then
                -- Context menu works on a single focused row.
                local action, count = MultiSelect.MultiSelectToggle(MS_CTX_LOOT, id, false)
                module.selectedItem = id

                if Options.IsDebugEnabled() and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickContextMenu):format(
                        tostring(id), tostring(action), tonumber(count) or 0
                    ))
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
                for _, name in ipairs(bossKill.players) do
                    if normalizedName == Strings.NormalizeLower(name) then
                        return name
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

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp,
            function(self, text)
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

                module.Loot:Log(self.itemId, winner, nil, nil, "LOGGER_EDIT_WINNER")
            end,
            function(self)
                self.raidId = module.selectedRaid
                self.itemId = module.selectedItem
            end
        )

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp,
            function(self, text)
                module.Loot:Log(self.itemId, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
            end,
            function(self) self.itemId = module.selectedItem end,
            validateRollValue
        )
    end
end

-- Raids list.
do
    module.Raids = module.Raids or {}
    local Raids = module.Raids
    local Store = module.Store
    local controller = ListController.MakeListController {
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
            Frames.SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)
            _G[n .. "ExportBtn"]:Disable() -- Not implemented.

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
            for i = 1, #KRT_Raids do
                local r = Core.EnsureRaidById(i)
                if r then
                    local it = {}
                    it.id = tonumber(r.raidNid)
                    it.seq = i
                    it.zone = r.zone
                    it.size = r.size
                    it.difficulty = tonumber(r.difficulty)
                    local mode = it.difficulty and ((it.difficulty == 3 or it.difficulty == 4) and "H" or "N") or "?"
                    it.sizeLabel = tostring(it.size or "") .. mode
                    it.date = r.startTime
                    it.dateFmt = date("%d/%m/%Y %H:%M", r.startTime)
                    out[i] = it
                end
            end
        end,

        rowName = function(n, _, i) return n .. "RaidBtn" .. i end,
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

        highlightFn = function(id) return MultiSelect.MultiSelectIsSelected(module._msRaidCtx, id) end,
        focusId = function()
            local selected = module.selectedRaid
            return selected and Core.GetRaidNidById(selected) or nil
        end,
        focusKey = function()
            local selected = module.selectedRaid
            local raidNid = selected and Core.GetRaidNidById(selected) or nil
            return tostring(raidNid or "nil")
        end,
        highlightKey = function() return MultiSelect.MultiSelectGetVersion(module._msRaidCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msRaidCtx),
                MultiSelect.MultiSelectCount(module._msRaidCtx))
        end,

        postUpdate = function(n)
            local sel = module.selectedRaid
            local raid = sel and Core.EnsureRaidById(sel) or nil

            local canSetCurrent = false
            if sel and raid and sel ~= Core.GetCurrentRaid() then
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
        end,

        sorters = {
            id = function(a, b, asc)
                return CompareNumbers(a.seq or a.id, b.seq or b.id, asc, 0)
            end,
            date = function(a, b, asc) return CompareNumbers(a.date, b.date, asc, 0) end,
            zone = function(a, b, asc) return CompareStrings(a.zone, b.zone, asc) end,
            size = function(a, b, asc) return CompareNumbers(a.size, b.size, asc, 0) end,
        },
    }

    Raids._ctrl = controller
    ListController.BindListController(Raids, controller)

    function Raids:SetCurrent(btn)
        if not btn then return end
        local sel = module.selectedRaid
        if not sel then return end
        if module.Actions:SetCurrentRaid(sel) then
            -- Context change: clear dependent selections and redraw all module panels.
            SetSelectedRaid(sel)
            module:ResetSelections()
            triggerSelectionEvent(module, "selectedRaid", "ui")
        end
    end

    do
        local function DeleteRaids()
            local ctx = module._msRaidCtx
            local ids = MultiSelect.MultiSelectGetSelected(ctx)
            if not (ids and #ids > 0) then return end

            local raidNids = {}
            local seenNids = {}
            for i = 1, #ids do
                local nid = tonumber(ids[i])
                if nid and not seenNids[nid] then
                    seenNids[nid] = true
                    raidNids[#raidNids + 1] = nid
                end
            end
            if #raidNids == 0 then return end

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

            local n = KRT_Raids and #KRT_Raids or 0
            local newFocus = nil
            if n > 0 then
                newFocus = prevFocusNid and Core.GetRaidIdByNid(prevFocusNid) or nil
                if not newFocus then
                    local base = tonumber(prevFocus) or n
                    if base > n then base = n end
                    if base < 1 then base = 1 end
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

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, DeleteRaids)
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
        if raidId == nil then
            addon:warn(Diag.W.LogLoggerSelectRaidPayloadInvalid:format(tostring(raidId), tostring(reason)))
            return
        end
        if raidIdType ~= "number" and raidIdType ~= "string" then
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

        controller:Touch()
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
        if not isLoggerViewingCurrentRaid() then
            return
        end

        requestRosterBoundListsRefresh()
    end)
end

-- Boss list.
do
    module.Boss = module.Boss or {}
    local Boss = module.Boss
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions

    local controller = ListController.MakeListController {
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
            if not raid then return end
            View:FillBossList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "BossBtn" .. i end,
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

        highlightFn = function(id) return MultiSelect.MultiSelectIsSelected(module._msBossCtx, id) end,
        focusId = function() return module.selectedBoss end,
        focusKey = function() return tostring(module.selectedBoss or "nil") end,
        highlightKey = function() return MultiSelect.MultiSelectGetVersion(module._msBossCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msBossCtx),
                MultiSelect.MultiSelectCount(module._msBossCtx))
        end,

        postUpdate = function(n)
            local hasRaid = module.selectedRaid
            local hasBoss = module.selectedBoss
            UIPrimitives.EnableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            UIPrimitives.EnableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            local bossSelCount = MultiSelect.MultiSelectCount(module._msBossCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, bossSelCount)
            UIPrimitives.EnableDisable(delBtn, (bossSelCount and bossSelCount > 0) or false)
        end,

        sorters = {
            -- Sort by the displayed sequential number, not the stable nid.
            id = function(a, b, asc) return CompareNumbers(a.seq, b.seq, asc, 0) end,
            name = function(a, b, asc) return CompareStrings(a.name, b.name, asc) end,
            time = function(a, b, asc) return CompareNumbers(a.time, b.time, asc, 0) end,
            mode = function(a, b, asc) return CompareStrings(a.mode, b.mode, asc) end,
        },
    }

    Boss._ctrl = controller
    ListController.BindListController(Boss, controller)

    function Boss:Add() module.BossBox:Toggle() end

    function Boss:Edit() if module.selectedBoss then module.BossBox:Fill() end end

    do
        local function DeleteBosses()
            module:Run(function(_, rID)
                local ctx = module._msBossCtx
                local ids = MultiSelect.MultiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

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

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, DeleteBosses)
    end

    function Boss:GetName(bossNid, raidId)
        local rID = raidId or module.selectedRaid
        if not rID then return "" end
        bossNid = bossNid or module.selectedBoss
        if not bossNid then return "" end

        local raid = Store:GetRaid(rID)
        if not raid then return "" end
        local boss = raid and Store:GetBoss(raid, bossNid) or nil
        return boss and boss.name or ""
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function() controller:Dirty() end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectBoss, function() controller:Touch() end)
end

-- Boss attendees list.
do
    module.BossAttendees = module.BossAttendees or {}
    local BossAtt = module.BossAttendees
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions

    local controller = ListController.MakeListController {
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then title:SetText(L.StrBossAttendees) end
            local add = _G[n .. "AddBtn"]; if add then add:SetText(L.BtnAdd) end
            local rm = _G[n .. "RemoveBtn"]; if rm then rm:SetText(L.BtnRemove) end
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
            if not (raid and bID) then return end
            View:FillBossAttendeesList(out, raid, bID)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
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

        highlightFn = function(id) return MultiSelect.MultiSelectIsSelected(module._msBossAttCtx, id) end,
        focusId = function() return module.selectedBossPlayer end,
        focusKey = function() return tostring(module.selectedBossPlayer or "nil") end,
        highlightKey = function() return MultiSelect.MultiSelectGetVersion(module._msBossAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msBossAttCtx),
                MultiSelect.MultiSelectCount(module._msBossAttCtx))
        end,

        postUpdate = function(n)
            local bSel = module.selectedBoss
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = MultiSelect.MultiSelectCount(module._msBossAttCtx)
            if addBtn then
                UIPrimitives.EnableDisable(addBtn, bSel and ((attSelCount or 0) == 0))
            end
            if removeBtn then
                UIPrimitives.SetButtonCount(removeBtn, L.BtnRemove, attSelCount)
                UIPrimitives.EnableDisable(removeBtn, bSel and ((attSelCount or 0) > 0))
            end
        end,

        sorters = {
            name = function(a, b, asc) return CompareStrings(a.name, b.name, asc) end,
        },
    }

    BossAtt._ctrl = controller
    ListController.BindListController(BossAtt, controller)

    function BossAtt:Add() module.AttendeesBox:Toggle() end

    do
        local function DeleteAttendees()
            module:Run(function(_, rID)
                local bNid = module.selectedBoss
                local ctx = module._msBossAttCtx
                local ids = MultiSelect.MultiSelectGetSelected(ctx)
                if not (bNid and ids and #ids > 0) then return end

                for i = 1, #ids do
                    Actions:DeleteBossAttendee(rID, bNid, ids[i])
                end

                MultiSelect.MultiSelectClear(ctx)
                module.selectedBossPlayer = nil
            end)
        end

        function BossAtt:Delete()
            local ctx = module._msBossAttCtx
            if MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
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

    local controller = ListController.MakeListController {
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
            if not raid then return end
            View:FillRaidAttendeesList(out, raid)
        end,

        rowName = function(n, _, i) return n .. "PlayerBtn" .. i end,
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

        highlightFn = function(id) return MultiSelect.MultiSelectIsSelected(module._msRaidAttCtx, id) end,
        focusId = function() return module.selectedPlayer end,
        focusKey = function() return tostring(module.selectedPlayer or "nil") end,
        highlightKey = function() return MultiSelect.MultiSelectGetVersion(module._msRaidAttCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msRaidAttCtx),
                MultiSelect.MultiSelectCount(module._msRaidAttCtx))
        end,

        postUpdate = function(n)
            local deleteBtn = _G[n .. "DeleteBtn"]
            if deleteBtn then
                local attSelCount = MultiSelect.MultiSelectCount(module._msRaidAttCtx)
                UIPrimitives.SetButtonCount(deleteBtn, L.BtnDelete, attSelCount)
                UIPrimitives.EnableDisable(deleteBtn, (attSelCount and attSelCount > 0) or false)
            end

            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                -- Update is only meaningful for the current raid session while actively raiding.
                local can = addon.IsInRaid() and Core.GetCurrentRaid() and module.selectedRaid
                    and (tonumber(Core.GetCurrentRaid()) == tonumber(module.selectedRaid))
                UIPrimitives.EnableDisable(addBtn, can)
            end
        end,

        sorters = {
            name = function(a, b, asc) return CompareStrings(a.name, b.name, asc) end,
            join = function(a, b, asc) return CompareNumbers(a.join, b.join, asc, 0) end,
            leave = function(a, b, asc)
                local missing = asc and math.huge or -math.huge
                return CompareNumbers(a.leave, b.leave, asc, missing)
            end,
        },
    }

    RaidAtt._ctrl = controller
    ListController.BindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function RaidAtt:Add()
        module:Run(function(_, rID)
            local sel = tonumber(rID)
            if not sel then return end

            if not addon.IsInRaid() then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotInRaid)
                return
            end

            if not (Core.GetCurrentRaid() and tonumber(Core.GetCurrentRaid()) == sel) then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotCurrent)
                return
            end

            -- Update the roster from the live in-game raid roster.
            addon.Raid:UpdateRaidRoster()

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
        local function DeleteAttendees()
            module:Run(function(_, rID)
                local ctx = module._msRaidAttCtx
                local ids = MultiSelect.MultiSelectGetSelected(ctx)
                if not (ids and #ids > 0) then return end

                local removed = Actions:DeleteRaidAttendeeMany(rID, ids)
                if removed and removed > 0 then
                    MultiSelect.MultiSelectClear(ctx)
                    module.selectedPlayer = nil

                    -- Player filters changed: clear boss-attendees selection too.
                    module.selectedBossPlayer = nil
                    MultiSelect.MultiSelectClear(module._msBossAttCtx)

                    -- Filters changed: reset loot selection.
                    module.selectedItem = nil
                    MultiSelect.MultiSelectClear(module._msLootCtx)
                end
            end)
        end

        function RaidAtt:Delete()
            local ctx = module._msRaidAttCtx
            if MultiSelect.MultiSelectCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, DeleteAttendees)
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function() controller:Dirty() end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectPlayer, function() controller:Touch() end)
end

-- Loot list (filters by selected boss and player).
do
    module.Loot = module.Loot or {}
    local Loot = module.Loot
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions

    local function updateSourceHeaderState(frameName)
        local header = frameName and _G[frameName .. "HeaderSource"]
        if not header then return end

        local canSortSource = module.selectedBoss == nil
        if header.EnableMouse then
            header:EnableMouse(canSortSource)
        end
        if header.SetAlpha then
            header:SetAlpha(canSortSource and 1 or 0.6)
        end
    end

    local controller = ListController.MakeListController {
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
            if not raid then return end

            local bID = module.selectedBoss
            local pID = module.selectedBossPlayer or module.selectedPlayer
            local p = pID and Store:GetPlayer(raid, pID) or nil
            local pName = p and p.name or nil

            View:FillLootList(out, raid, bID, pName)
        end,

        rowName = function(n, _, i) return n .. "ItemBtn" .. i end,
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
                ui.Name:SetText(addon.WrapTextInColorCode(
                    nameText,
                    Colors.NormalizeHexColor(itemColors[(it.itemRarity or 1) + 1])
                ))
            end

            local selectedBoss = module.selectedBoss
            if selectedBoss and tonumber(it.bossNid) == tonumber(selectedBoss) then
                ui.Source:SetText("")
            else
                ui.Source:SetText(it.sourceName or "")
            end

            local r, g, b = Colors.GetClassColor(addon.Raid:GetPlayerClass(it.looter))
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

        highlightFn = function(id) return MultiSelect.MultiSelectIsSelected(module._msLootCtx, id) end,
        focusId = function() return module.selectedItem end,
        focusKey = function() return tostring(module.selectedItem or "nil") end,
        highlightKey = function() return MultiSelect.MultiSelectGetVersion(module._msLootCtx) end,
        highlightDebugTag = "LoggerSelect",
        highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module._msLootCtx),
                MultiSelect.MultiSelectCount(module._msLootCtx))
        end,

        postUpdate = function(n)
            updateSourceHeaderState(n)

            local lootSelCount = MultiSelect.MultiSelectCount(module._msLootCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, lootSelCount)
            UIPrimitives.EnableDisable(delBtn, (lootSelCount or 0) > 0)
        end,

        sorters = {
            id = function(a, b, asc) return CompareLootTie(a, b, asc) end,
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
    }

    Loot._ctrl = controller
    ListController.BindListController(Loot, controller)

    function Loot:Sort(key)
        if key == "source" and module.selectedBoss then
            return
        end
        controller:Sort(key)
    end

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
            module:Run(function(_, rID)
                local ctx = module._msLootCtx
                local selected = MultiSelect.MultiSelectGetSelected(ctx)
                if not selected or #selected == 0 then return end

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

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ITEM", L.StrConfirmDeleteItem, DeleteItem)
    end

    function Loot:Log(itemID, looter, rollType, rollValue, source, raidIDOverride)
        local raidID
        if raidIDOverride then
            raidID = raidIDOverride
        else
            -- If the module window is open and browsing an old raid, selectedRaid may differ from Core.GetCurrentRaid().
            -- Runtime sources must always write into the CURRENT raid session.
            -- Logger UI edits target selectedRaid.
            local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
            if isLoggerSource then
                raidID = module.selectedRaid or Core.GetCurrentRaid()
            else
                raidID = Core.GetCurrentRaid() or module.selectedRaid
            end
        end
        addon:trace(Diag.D.LogLoggerLootLogAttempt:format(tostring(source), tostring(raidID), tostring(itemID),
            tostring(looter), tostring(rollType), tostring(rollValue), tostring(Core.GetLastBoss())))
        local raid = raidID and Core.EnsureRaidById(raidID) or nil
        if not raid then
            addon:error(Diag.E.LogLoggerNoRaidSession:format(tostring(raidID), tostring(itemID)))
            return false
        end

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
        if not Core.GetLastBoss() then
            addon:debug(Diag.D.LogLoggerRecordedNoBossContext:format(raidID, tostring(itemID), tostring(it.itemLink)))
        end
        return true
    end

    Bus.RegisterCallback(InternalEvents.LoggerLootLogRequest, function(_, request)
        if type(request) ~= "table" then
            addon:error(Diag.E.LogLoggerLootLogRequestPayloadInvalid:format(type(request)))
            return
        end
        local raidId = request.raidId or request.raidID
        request.ok = Loot:Log(request.itemID, request.looter, request.rollType, request.rollValue,
            request.source, raidId) == true
    end)

    local function Reset() controller:Dirty() end
    Bus.RegisterCallbacks(
        {
            InternalEvents.LoggerSelectRaid,
            InternalEvents.LoggerSelectBoss,
            InternalEvents.LoggerSelectPlayer,
            InternalEvents.LoggerSelectBossPlayer,
            InternalEvents.RaidLootUpdate,
        },
        Reset
    )
    Bus.RegisterCallback(InternalEvents.LoggerSelectItem, function() controller:Touch() end)
end

-- Add/edit boss popup (time/mode normalization).
do
    module.BossBox = module.BossBox or {}
    local Box = module.BossBox
    local Store = module.Store

    local frameName, localized, isEdit = nil, false, false
    local raidData, bossData, tempDate = {}, {}, {}
    local getFrame = Frames.MakeFrameGetter("KRTLoggerBossBox")

    function Box:OnLoad(frame)
        frameName = Frames.InitModuleFrame(Box, frame, {
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

        local boxFrame = _G[frameName]
        if boxFrame and not boxFrame._krtBound then
            Frames.SafeSetScript(saveBtn, "OnClick", function()
                Box:Save()
            end)
            Frames.SafeSetScript(cancelBtn, "OnClick", function()
                Box:Hide()
            end)
            Frames.SafeSetScript(_G[frameName .. "Name"], "OnEnterPressed", function()
                Box:Save()
            end)
            Frames.SafeSetScript(_G[frameName .. "Difficulty"], "OnEnterPressed", function()
                Box:Save()
            end)
            Frames.SafeSetScript(_G[frameName .. "Time"], "OnEnterPressed", function()
                Box:Save()
            end)
            boxFrame._krtBound = true
        end
    end

    local uiController = UIScaffold.BootstrapModuleUi(Box, getFrame, function()
        Box:UpdateUIFrame()
    end)

    function Box:EnsureUI()
        local frame = getFrame()
        if not frame then
            return nil
        end
        if not frameName then
            self:OnLoad(frame)
        end
        return frame
    end

    function Box:Toggle()
        if not self:EnsureUI() then
            return
        end
        return uiController:Toggle()
    end

    function Box:Hide()
        if not self:EnsureUI() then
            return
        end
        return uiController:Hide()
    end

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    function Box:Fill()
        local rID, bID = module.selectedRaid, module.selectedBoss
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
        local rID = module.selectedRaid
        if not rID then return end

        local name = Strings.TrimText(_G[frameName .. "Name"]:GetText())
        local modeT = Strings.NormalizeLower(_G[frameName .. "Difficulty"]:GetText())
        local bTime = Strings.TrimText(_G[frameName .. "Time"]:GetText())

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
        if not savedNid then return end

        self:Hide()
        module:ResetSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function Box:CancelAddEdit()
        Frames.ResetEditBox(_G[frameName .. "Name"])
        Frames.ResetEditBox(_G[frameName .. "Difficulty"])
        Frames.ResetEditBox(_G[frameName .. "Time"])
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    function Box:UpdateUIFrame()
        if not localized then
            Frames.SetTooltip(_G[frameName .. "Name"], L.StrBossNameHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(_G[frameName .. "Difficulty"], L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(_G[frameName .. "Time"], L.StrBossTimeHelp, "ANCHOR_RIGHT")
            localized = true
        end
        UIPrimitives.SetText(_G[frameName .. "Title"], L.StrEditBoss, L.StrAddBoss, isEdit)
    end
end

-- Add attendee popup.
do
    module.AttendeesBox = module.AttendeesBox or {}
    local Box = module.AttendeesBox

    local frameName
    local getFrame = Frames.MakeFrameGetter("KRTLoggerPlayerBox")

    function Box:OnLoad(frame)
        frameName = Frames.InitModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = function()
                Frames.ResetEditBox(_G[frameName .. "Name"])
            end,
            hookOnHide = function()
                Frames.ResetEditBox(_G[frameName .. "Name"])
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

        local boxFrame = _G[frameName]
        if boxFrame and not boxFrame._krtBound then
            Frames.SafeSetScript(addBtn, "OnClick", function()
                Box:Save()
            end)
            Frames.SafeSetScript(cancelBtn, "OnClick", function()
                Box:Hide()
            end)
            Frames.SafeSetScript(_G[frameName .. "Name"], "OnEnterPressed", function()
                Box:Save()
            end)
            boxFrame._krtBound = true
        end
    end

    local uiController = UIScaffold.BootstrapModuleUi(Box, getFrame)

    function Box:EnsureUI()
        local frame = getFrame()
        if not frame then
            return nil
        end
        if not frameName then
            self:OnLoad(frame)
        end
        return frame
    end

    function Box:Toggle()
        if not self:EnsureUI() then
            return
        end
        return uiController:Toggle()
    end

    function Box:Hide()
        if not self:EnsureUI() then
            return
        end
        return uiController:Hide()
    end

    function Box:Save()
        local rID, bID = module.selectedRaid, module.selectedBoss
        local name = Strings.TrimText(_G[frameName .. "Name"]:GetText())
        if module.Actions:AddBossAttendee(rID, bID, name) then
            self:Toggle()
            triggerSelectionEvent(module, "selectedBoss")
        end
    end
end

