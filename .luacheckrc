std = "lua51"
max_line_length = false

include_files = {
    "!KRT/**/*.lua",
    "core/**/*.lua",
    "ui/**/*.lua",
    "services/**/*.lua"
}

exclude_files = {
    ".git",
    ".github",
    ".luarocks",
    "!KRT/Libs/**/*.lua"
}

ignore = {
    "212/self",   -- ignora 'self' non usato (per mixin)
    "212/event"   -- ignora 'event' non usato (per eventi WoW)
}

globals = {
    -- Unit Functions
    "UnitName", "UnitClass", "UnitLevel", "UnitRace", "UnitSex",
    "UnitFactionGroup", "UnitHealth", "UnitHealthMax", "UnitIsDead",
    "UnitIsConnected", "UnitExists", "UnitGUID", "UnitIsUnit",
    "UnitIsPlayer", "UnitInRaid", "UnitInParty", "UnitAffectingCombat",

    -- Chat and Communication
    "SendChatMessage", "DEFAULT_CHAT_FRAME", "ChatFrame_AddMessageEventFilter",
    "GetNumPartyMembers", "GetNumRaidMembers", "IsInGroup", "IsInRaid",

    -- Frames and Widgets
    "CreateFrame", "UIParent", "GameTooltip", "SetItemRef",
    "ToggleDropDownMenu", "UIDropDownMenu_AddButton", "UIDropDownMenu_Initialize",

    -- Loot and Inventory
    "GetItemInfo", "GetLootRollItemInfo", "RollOnLoot", "ConfirmLootRoll",
    "LootSlotHasItem", "LootSlotIsItem", "LootSlotIsCoin",

    -- Sound and Media
    "PlaySound", "PlaySoundFile", "StopSound",

    -- Utility / Misc
    "LibStub", "SlashCmdList", "hooksecurefunc", "GetAddOnMetadata", "GetLocale", "Mixin",

    -- Minimap / Tooltip
    "Minimap", "UIErrorsFrame",

    -- Math / String (Lua built-ins)
    "strlower", "strtrim", "strsplit", "strjoin",
    "min", "max", "floor", "ceil",

    -- KRT Addon: SavedVariables & Globals
    "KRT", "KRT_CurrentRaid", "KRT_LastBoss", "KRT_Debug",
    "KRT_Players", "KRT_Raids", "KRT_Options", "KRT_Warnings",
    "KRT_Spammer", "KRT_ExportString", "KRT_SavedReserves", "KRT_NextReset",
    "KRT_FakeTooltip", "KRT_MINIMAP_GUI", "CUSTOM_CLASS_COLORS"
}
