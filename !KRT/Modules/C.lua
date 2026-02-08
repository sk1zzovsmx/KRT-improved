local addonName, addon        = ...
addon.C                       = addon.C or {}

local C                       = addon.C
local L                       = addon.L

C.ITEM_LINK_PATTERN           =
    "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?" ..
    "(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?"

-- Roll Types Enum
C.rollTypes                   = {
    MANUAL     = 0,
    MAINSPEC   = 1,
    OFFSPEC    = 2,
    RESERVED   = 3,
    FREE       = 4,
    BANK       = 5,
    DISENCHANT = 6,
    HOLD       = 7,
}

-- Roll Type Colored Display Text
C.lootTypesColored            = {
    [0] = "|cffc0c0c0" .. L.BtnManual .. "|r",
    [1] = "|cff20ff20" .. L.BtnMS .. "|r",
    [2] = "|cffffff9f" .. L.BtnOS .. "|r",
    [3] = "|cffa335ee" .. L.BtnSR .. "|r",
    [4] = "|cffffd200" .. L.BtnFree .. "|r",
    [5] = "|cffff7f00" .. L.BtnBank .. "|r",
    [6] = "|cffff2020" .. L.BtnDisenchant .. "|r",
    [7] = "|cffffffff" .. L.BtnHold .. "|r",
}

-- Item Quality Colors
C.itemColors                  = {
    [1] = "ff9d9d9d", -- Poor
    [2] = "ffffffff", -- Common
    [3] = "ff1eff00", -- Uncommon
    [4] = "ff0070dd", -- Rare
    [5] = "ffa335ee", -- Epic
    [6] = "ffff8000", -- Legendary
    [7] = "ffe6cc80", -- Artifact / Heirloom
}

-- Class Colors
C.CLASS_COLORS                = {
    ["UNKNOWN"]     = "ffffffff",
    ["DEATHKNIGHT"] = "ffc41f3b",
    ["DRUID"]       = "ffff7d0a",
    ["HUNTER"]      = "ffabd473",
    ["MAGE"]        = "ff40c7eb",
    ["PALADIN"]     = "fff58cba",
    ["PRIEST"]      = "ffffffff",
    ["ROGUE"]       = "fffff569",
    ["SHAMAN"]      = "ff0070de",
    ["WARLOCK"]     = "ff8787ed",
    ["WARRIOR"]     = "ffc79c6e",
}

-- Raid Target Markers
C.RAID_TARGET_MARKERS         = {
    "{circle}",
    "{diamond}",
    "{triangle}",
    "{moon}",
    "{square}",
    "{cross}",
    "{skull}",
}

C.K_COLOR                     = "fff58cba"
C.RT_COLOR                    = "aaf49141"
C.titleString                 = "|c" .. C.K_COLOR .. "K|r|c" .. C.RT_COLOR .. "RT|r : %s"

C.CHAT_OUTPUT_FORMAT          = "%s: %s"
C.CHAT_PREFIX                 = "Kader Raid Tools"
C.CHAT_PREFIX_SHORT           = "KRT"
C.CHAT_PREFIX_HEX             = C.K_COLOR

-- Multi-award pacing (seconds) to avoid spamming GiveMasterLoot on laggy servers.
C.ML_MULTI_AWARD_DELAY        = 0.2

C.LOOT_COUNTER_ROW_HEIGHT     = 25
C.RESERVES_ROW_HEIGHT         = 42
C.RESERVE_HEADER_HEIGHT       = 24
C.RESERVES_ITEM_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
