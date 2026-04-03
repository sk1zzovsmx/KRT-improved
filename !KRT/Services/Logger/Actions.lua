-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Strings = feature.Strings or addon.Strings
local Base64 = feature.Base64 or addon.Base64
local Core = feature.Core
local Services = feature.Services

local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs
local tonumber, tostring = tonumber, tostring
local time = time

-- ----- Internal state ----- --
addon.Services = addon.Services or {}
addon.Services.Logger = addon.Services.Logger or {}
addon.Services.Logger.Actions = addon.Services.Logger.Actions or {}

local Actions = addon.Services.Logger.Actions
local Store = addon.Services.Logger.Store

-- Controller binding (injected by Controllers/Logger.lua at setup time).
local _controller = nil
local _triggerSelectionEvent = nil

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

--- Bind the owning controller and its triggerSelectionEvent helper.
--- Called once from Controllers/Logger.lua after all files are loaded.
function Actions:BindController(ctrl, triggerFn)
    _controller = ctrl
    _triggerSelectionEvent = triggerFn
end

function Actions:RemoveAll(list, value)
    if not (list and value) then
        return
    end
    local i = addon.tIndexOf(list, value)
    while i do
        tremove(list, i)
        i = addon.tIndexOf(list, value)
    end
end

function Actions:Commit(raid, opts)
    if not raid then
        return
    end
    opts = opts or {}

    -- Rebuild canonical raid schema/runtime indexes after in-place mutations.
    Core.EnsureRaidSchema(raid)

    if opts.invalidate ~= false then
        Store:InvalidateIndexes(raid)
    end

    local log = _controller
    if not log then
        return
    end

    local changedBoss, changedPlayer, changedBossPlayer, changedItem = false, false, false, false

    local function clearBossSelection()
        if log.selectedBoss ~= nil then
            changedBoss = true
        end
        if log.selectedBossPlayer ~= nil then
            changedBossPlayer = true
        end
        if log.selectedItem ~= nil then
            changedItem = true
        end
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

    if _triggerSelectionEvent then
        if changedBoss then
            _triggerSelectionEvent(log, "selectedBoss")
        end
        if changedPlayer then
            _triggerSelectionEvent(log, "selectedPlayer")
        end
        if changedBossPlayer then
            _triggerSelectionEvent(log, "selectedBossPlayer")
        end
        if changedItem then
            _triggerSelectionEvent(log, "selectedItem")
        end
    end
end

function Actions:DeleteBoss(rID, bossNid)
    local raid = Store:GetRaid(rID)
    if not (raid and bossNid) then
        return 0
    end

    local _, bossIndex = Store:GetBoss(raid, bossNid)
    if not bossIndex then
        return 0
    end

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
    if not (raid and lootNid) then
        return false
    end
    local _, lootIndex = Store:GetLoot(raid, lootNid)
    if not lootIndex then
        return false
    end
    tremove(raid.loot, lootIndex)
    self:Commit(raid)
    return true
end

-- Bulk delete: removes multiple loot entries (by nid) with a single Commit()
-- Returns: number of removed entries
function Actions:DeleteLootMany(rID, lootNids)
    local raid = Store:GetRaid(rID)
    if not (raid and lootNids and raid.loot) then
        return 0
    end

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
    if not (raid and bossNid and playerNid) then
        return false
    end
    local bossKill = Store:GetBoss(raid, bossNid)
    if not (bossKill and bossKill.players and raid.players) then
        return false
    end
    local queryNid = tonumber(playerNid)
    if not queryNid or queryNid <= 0 then
        return false
    end
    self:RemoveAll(bossKill.players, queryNid)
    return true
end

function Actions:DeleteRaidAttendee(rID, playerNid)
    local raid = Store:GetRaid(rID)
    if not (raid and raid.players and playerNid) then
        return false
    end

    local queryNid = tonumber(playerNid)
    if not queryNid or queryNid <= 0 then
        return false
    end

    local _, playerIdx = Store:GetPlayer(raid, queryNid)
    if not playerIdx then
        return false
    end

    tremove(raid.players, playerIdx)

    -- Remove from all boss attendee lists.
    if raid.bossKills then
        for _, boss in ipairs(raid.bossKills) do
            if boss and boss.players then
                self:RemoveAll(boss.players, queryNid)
            end
        end
    end

    -- Remove loot won by removed player.
    if raid.loot then
        for i = #raid.loot, 1, -1 do
            local loot = raid.loot[i]
            local looterNid = loot and tonumber(loot.looterNid) or nil
            if looterNid and looterNid == queryNid then
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
    if not (raid and raid.players and playerNids and #playerNids > 0) then
        return 0
    end

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
    table.sort(ids, function(a, b)
        return a > b
    end)

    -- Collect removed NIDs + remove players from raid.players.
    local removedNids = {}
    local removed = 0
    for i = 1, #ids do
        local idx = ids[i]
        local p = raid.players[idx]
        local playerNid2 = p and tonumber(p.playerNid)
        if playerNid2 and playerNid2 > 0 then
            removedNids[playerNid2] = true
            tremove(raid.players, idx)
            removed = removed + 1
        end
    end

    if removed == 0 then
        return 0
    end

    -- Remove from all boss attendee lists.
    if raid.bossKills then
        for _, boss in ipairs(raid.bossKills) do
            if boss and boss.players then
                for j = #boss.players, 1, -1 do
                    local attendeeNid = tonumber(boss.players[j])
                    if attendeeNid and removedNids[attendeeNid] then
                        tremove(boss.players, j)
                    end
                end
            end
        end
    end

    -- Remove loot won by removed players.
    if raid.loot then
        for j = #raid.loot, 1, -1 do
            local loot = raid.loot[j]
            local looterNid = loot and tonumber(loot.looterNid) or nil
            if looterNid and removedNids[looterNid] then
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
    if not raid then
        return false
    end

    if Core.GetCurrentRaid() and Core.GetCurrentRaid() == sel then
        addon:error(L.ErrCannotDeleteRaid)
        return false
    end

    local raidStore = Core.GetRaidStoreOrNil("Logger.Actions.DeleteRaid", { "DeleteRaid" })
    local removedIdx = sel
    if raidStore then
        local deleted, idx = raidStore:DeleteRaid(raid.raidNid)
        if not deleted then
            return false
        end
        removedIdx = idx or removedIdx
    else
        return false
    end

    if Core.GetCurrentRaid() and Core.GetCurrentRaid() > removedIdx then
        Core.SetCurrentRaid(Core.GetCurrentRaid() - 1)
    end

    return true
end

function Actions:DeleteRaidByNid(raidNid)
    local nid = tonumber(raidNid)
    if not nid then
        return false
    end
    local raid, sel = Core.EnsureRaidByNid(nid)
    if not (raid and sel) then
        return false
    end

    local currentRaidNid = Core.GetRaidNidById(Core.GetCurrentRaid())
    if currentRaidNid and tonumber(currentRaidNid) == nid then
        addon:error(L.ErrCannotDeleteRaid)
        return false
    end

    local raidStore = Core.GetRaidStoreOrNil("Logger.Actions.DeleteRaidByNid", { "DeleteRaid" })
    local removedIdx = sel
    if raidStore then
        local deleted, idx = raidStore:DeleteRaid(nid)
        if not deleted then
            return false
        end
        removedIdx = idx or removedIdx
    else
        return false
    end

    if Core.GetCurrentRaid() and Core.GetCurrentRaid() > removedIdx then
        Core.SetCurrentRaid(Core.GetCurrentRaid() - 1)
    end

    return true
end

function Actions:SetCurrentRaid(rID)
    local sel = tonumber(rID)
    local raid = sel and Core.EnsureRaidById(sel) or nil
    if not (sel and raid) then
        return false
    end

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
    local groupSize = Services.Raid:GetRaidSize()
    if not raidSize or raidSize ~= groupSize then
        addon:error(L.ErrCannotSetCurrentRaidSize)
        return false
    end

    if Services.Raid:Expired(sel) then
        addon:error(L.ErrCannotSetCurrentRaidReset)
        return false
    end

    Core.SetCurrentRaid(sel)
    Core.SetLastBoss(nil)

    -- Sync roster/dropdowns immediately so subsequent logging targets the selected raid.
    Services.Raid:UpdateRaidRoster()

    addon:info(L.LogRaidSetCurrent:format(sel, tostring(raid.zone), raidSize))
    return true
end

-- Upsert boss kill (edit if bossNid provided, otherwise append new boss kill).
-- Returns bossNid on success, nil on failure.
function Actions:UpsertBossKill(rID, bossNid, name, ts, mode)
    local raid = Store:GetRaid(rID)
    if not raid then
        return nil
    end

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
    local playerName, _, player = Store:FindRaidPlayerByNormName(raid, normalizedName)
    local playerNid = tonumber(player and player.playerNid)
    if not (playerName and playerNid and playerNid > 0) then
        addon:error(L.ErrAttendeesInvalidName)
        return false
    end

    for i = 1, #bossKill.players do
        if tonumber(bossKill.players[i]) == playerNid then
            addon:error(L.ErrAttendeesPlayerExists)
            return false
        end
    end

    tinsert(bossKill.players, playerNid)
    addon:info(L.StrAttendeesAddSuccess)
    self:Commit(raid, { invalidate = false })
    return true
end
