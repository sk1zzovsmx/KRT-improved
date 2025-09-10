local addonName, addon = ...
addon.C               = addon.C or {}

local C               = addon.C
local L               = addon.L

C.ITEM_LINK_PATTERN =
    "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?" ..
    "(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?"

-- Roll Types Enum
C.rollTypes = {
    MAINSPEC   = 1,
    OFFSPEC    = 2,
    RESERVED   = 3,
    FREE       = 4,
    BANK       = 5,
    DISENCHANT = 6,
    HOLD       = 7,
    DKP        = 8,
}

-- Roll Type Display Text
C.lootTypesText = {
    L.BtnMS,
    L.BtnOS,
    L.BtnSR,
    L.BtnFree,
    L.BtnBank,
    L.BtnDisenchant,
    L.BtnHold,
}

-- Roll Type Colored Display Text
C.lootTypesColored = {
    "|cff20ff20" .. L.BtnMS .. "|r",
    "|cffffff9f" .. L.BtnOS .. "|r",
    "|cffa335ee" .. L.BtnSR .. "|r",
    "|cffffd200" .. L.BtnFree .. "|r",
    "|cffff7f00" .. L.BtnBank .. "|r",
    "|cffff2020" .. L.BtnDisenchant .. "|r",
    "|cffffffff" .. L.BtnHold .. "|r",
    "|cff20ff20DKP|r",
}

-- Item Quality Colors
C.itemColors = {
    [1] = "ff9d9d9d", -- Poor
    [2] = "ffffffff", -- Common
    [3] = "ff1eff00", -- Uncommon
    [4] = "ff0070dd", -- Rare
    [5] = "ffa335ee", -- Epic
    [6] = "ffff8000", -- Legendary
    [7] = "ffe6cc80", -- Artifact / Heirloom
}

-- Class Colors
C.CLASS_COLORS = {
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
C.RAID_TARGET_MARKERS = {
    "{circle}",
    "{diamond}",
    "{triangle}",
    "{moon}",
    "{square}",
    "{cross}",
    "{skull}",
}

C.K_COLOR  = "fff58cba"
C.RT_COLOR = "aaf49141"
C.titleString = "|c" .. C.K_COLOR .. "K|r|c" .. C.RT_COLOR .. "RT|r : %s"

