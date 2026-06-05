-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: addon.Services.Raid loot-method automation APIs
-- events: listens forwarded PLAYER_TARGET_CHANGED through Master; shows StaticPopup confirmation
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Bus = feature.Bus
local Database = feature.Database
local Events = feature.Events
local Options = feature.Options
local Services = feature.Services

local tostring, tonumber, type = tostring, tonumber, type

local GetTime = GetTime
local GetLootMethod = GetLootMethod
local SetLootMethod = SetLootMethod
local StaticPopup_Show = StaticPopup_Show
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitInRaid = UnitInRaid
local UnitIsDead = UnitIsDead
local UnitName = UnitName

local AUTO_MASTER_LOOT_COOLDOWN_SECONDS = 3
local DEFAULT_AUTO_MASTER_LOOT_NOTICE_SECONDS = 1.25
local MIN_AUTO_MASTER_LOOT_NOTICE_SECONDS = 0.1
local MAX_AUTO_MASTER_LOOT_NOTICE_SECONDS = 5
local GROUP_LOOT_RESTORE_POPUP_KEY = "KRT_CONFIRM_GROUP_LOOT_RESTORE"

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Raid")
local Raid = Services.Raid
local module = Raid

Options.AddNamespace("Master", {
    autoMasterLootOnBossTarget = false,
    autoMasterLootNoticeSeconds = 1.25,
    askGroupLootAfterBossLoot = false,
})

local state = {
    lastAutoMasterAt = 0,
    lastAutoMasterBoss = nil,
    lootWindowWasBoss = false,
    lootWindowWasMasterLoot = false,
    lootWindowPromptShown = false,
}

-- ----- Private helpers ----- --
local function getOption(key)
    local cfg = Options and Options.Get and Options.Get("Master")
    if cfg and cfg.Get then
        return cfg:Get(key)
    end
    return nil
end

local function getLootMethodName()
    if type(GetLootMethod) ~= "function" then
        return nil
    end
    local method = GetLootMethod()
    if type(method) ~= "string" or method == "" then
        return nil
    end
    return method
end

local function getAutoMasterLootNoticeSeconds()
    local seconds = tonumber(getOption("autoMasterLootNoticeSeconds")) or DEFAULT_AUTO_MASTER_LOOT_NOTICE_SECONDS
    if seconds < MIN_AUTO_MASTER_LOOT_NOTICE_SECONDS then
        return MIN_AUTO_MASTER_LOOT_NOTICE_SECONDS
    end
    if seconds > MAX_AUTO_MASTER_LOOT_NOTICE_SECONDS then
        return MAX_AUTO_MASTER_LOOT_NOTICE_SECONDS
    end
    return seconds
end

local function hasRaidLeaderAuthority()
    if type(UnitInRaid) ~= "function" or not UnitInRaid("player") then
        return false
    end
    if not (module and module.GetPlayerRoleState) then
        return false
    end
    local role = module:GetPlayerRoleState()
    return role and role.isLeader == true
end

local function getPlayerName()
    if Database and Database.GetPlayerName then
        local dbName = Database.GetPlayerName()
        if dbName and dbName ~= "" then
            return dbName
        end
    end
    return type(UnitName) == "function" and UnitName("player") or nil
end

local function getTargetBossInfo(allowDead)
    if type(UnitExists) ~= "function" or not UnitExists("target") then
        return nil
    end
    if not allowDead and type(UnitIsDead) == "function" and UnitIsDead("target") then
        return nil
    end

    local guid = type(UnitGUID) == "function" and UnitGUID("target") or nil
    local npcId = guid and feature.GetCreatureId and feature.GetCreatureId(guid) or nil
    local bossIds = feature.BossIDs and feature.BossIDs.BossIDs
    if not (npcId and bossIds and bossIds[tonumber(npcId)] == true) then
        return nil
    end

    return {
        name = type(UnitName) == "function" and UnitName("target") or nil,
        npcId = tonumber(npcId),
    }
end

local function ensureGroupLootRestorePopup()
    if type(StaticPopupDialogs) ~= "table" then
        return false
    end
    if StaticPopupDialogs[GROUP_LOOT_RESTORE_POPUP_KEY] then
        return true
    end

    StaticPopupDialogs[GROUP_LOOT_RESTORE_POPUP_KEY] = {
        text = L.PopupGroupLootRestoreText,
        button1 = L.BtnGroupLoot,
        button2 = L.BtnKeepMasterLoot,
        OnAccept = function()
            module:RestoreGroupLoot("popup")
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
    return true
end

local function showCenterNotice(message)
    if not message or message == "" then
        return false
    end
    local InternalEvents = Events and Events.Internal
    if Bus and Bus.TriggerEvent and InternalEvents and InternalEvents.ScreenNotice then
        Bus.TriggerEvent(InternalEvents.ScreenNotice, message, getAutoMasterLootNoticeSeconds())
        return true
    end
    return false
end

local function clearLootWindowPromptState()
    state.lootWindowWasBoss = false
    state.lootWindowWasMasterLoot = false
    state.lootWindowPromptShown = false
end

-- ----- Public methods ----- --
function module:HandleAutoMasterLootTargetChanged()
    -- PLAYER_TARGET_CHANGED
    if getOption("autoMasterLootOnBossTarget") ~= true then
        return false
    end
    if not hasRaidLeaderAuthority() then
        return false
    end
    if getLootMethodName() == "master" then
        return false
    end
    if type(SetLootMethod) ~= "function" then
        return false
    end

    local boss = getTargetBossInfo(false)
    if not boss then
        return false
    end

    local now = type(GetTime) == "function" and GetTime() or 0
    if state.lastAutoMasterBoss == boss.name and (now - (tonumber(state.lastAutoMasterAt) or 0)) < AUTO_MASTER_LOOT_COOLDOWN_SECONDS then
        return false
    end

    local playerName = getPlayerName()
    if not playerName or playerName == "" then
        return false
    end

    showCenterNotice(L.MsgAutoMasterLootScreen or "Boss targeted, auto switch to Master Loot.")
    SetLootMethod("master", playerName)
    state.lastAutoMasterAt = now
    state.lastAutoMasterBoss = boss.name
    addon:info((L.MsgAutoMasterLootSet or "KRT: Loot method set to Master Loot for %s."):format(tostring(boss.name or "Unknown")))
    return true
end

function module:NotifyLootWindowOpened()
    clearLootWindowPromptState()
    if getOption("askGroupLootAfterBossLoot") ~= true then
        return false
    end
    if not hasRaidLeaderAuthority() then
        return false
    end
    state.lootWindowWasMasterLoot = getLootMethodName() == "master"
    state.lootWindowWasBoss = getTargetBossInfo(true) ~= nil
    return state.lootWindowWasMasterLoot and state.lootWindowWasBoss
end

function module:NotifyLootWindowCleared()
    if getOption("askGroupLootAfterBossLoot") ~= true then
        return false
    end
    if state.lootWindowPromptShown or not state.lootWindowWasMasterLoot or not state.lootWindowWasBoss then
        return false
    end
    if not hasRaidLeaderAuthority() or getLootMethodName() ~= "master" then
        clearLootWindowPromptState()
        return false
    end
    if not ensureGroupLootRestorePopup() or type(StaticPopup_Show) ~= "function" then
        return false
    end

    state.lootWindowPromptShown = true
    StaticPopup_Show(GROUP_LOOT_RESTORE_POPUP_KEY)
    return true
end

function module:RestoreGroupLoot(source)
    if not hasRaidLeaderAuthority() or type(SetLootMethod) ~= "function" then
        return false
    end
    if getLootMethodName() ~= "master" then
        clearLootWindowPromptState()
        return false
    end

    SetLootMethod("group")
    clearLootWindowPromptState()
    addon:info(L.MsgGroupLootRestored or "KRT: Loot method set to Group Loot.")
    return true, source
end

function module:ClearLootMethodAutomationState()
    clearLootWindowPromptState()
end

local registry = feature.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Services/Raid/LootMethod", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Services/Raid/Capabilities",
        },
    })
    registry.SetLoaded("Services/Raid/LootMethod")
end
