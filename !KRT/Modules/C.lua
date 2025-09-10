local addonName, addon = ...
addon.C               = addon.C or {}

local C               = addon.C
local L               = addon.L

local Compat          = addon:GetLib("LibCompat-1.0", true)
if Compat and Compat.Embed then
    Compat:Embed(addon)
end

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
    addon:WrapTextInColorCode(L.BtnMS, "ff" .. GREEN_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode(L.BtnOS, "ff" .. LIGHTYELLOW_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode(L.BtnSR, "ffa335ee"),
    addon:WrapTextInColorCode(L.BtnFree, "ff" .. NORMAL_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode(L.BtnBank, "ff" .. ORANGE_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode(L.BtnDisenchant, "ff" .. RED_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode(L.BtnHold, "ff" .. HIGHLIGHT_FONT_COLOR_CODE:sub(5)),
    addon:WrapTextInColorCode("DKP", "ff" .. GREEN_FONT_COLOR_CODE:sub(5)),
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
C.titleString = addon:WrapTextInColorCode("K", C.K_COLOR)
    .. addon:WrapTextInColorCode("RT", C.RT_COLOR)
    .. " : %s"

