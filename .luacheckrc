std = "lua51"
max_line_length = false

include_files = {
    "!KRT/**/*.lua"
}

exclude_files = {
    ".git",
    ".github",
    ".luarocks",
    "!KRT/Libs/**/*.lua"
}

ignore = {
    "212/self",   -- ignora self non usato (per mixin)
    "212/event",  -- ignora event non usato (per eventi WoW)
}

globals = {
    -- WoW API core
    "CreateFrame", "DEFAULT_CHAT_FRAME", "UIParent", "SendChatMessage", "GetTime",
    "UnitName", "GetItemInfo", "PlaySound", "GameTooltip", "LibStub",
    "SlashCmdList", "RaidNotice_AddMessage", "IsInRaid", "IsInGroup",
    "GetNumRaidMembers", "GetNumPartyMembers", "GetLootRollItemInfo",
    "SetItemRef", "hooksecurefunc", "GetAddOnMetadata", "GetLocale", "Mixin",

    -- Lua base globali usate
    "strlower", "strtrim", "strsplit", "strjoin", "min", "max", "floor", "ceil",

    -- Oggetti globali comuni
    "GameTooltip", "UIParent", "Minimap",

    -- Tuo Addon: variabili salvate e namespace
    "KRT", "KRT_CurrentRaid", "KRT_LastBoss", "KRT_Debug",
    "KRT_Players", "KRT_Raids", "KRT_Options", "KRT_Warnings",
    "KRT_Spammer", "KRT_ExportString", "KRT_SavedReserves", "KRT_NextReset",
    "KRT_FakeTooltip", "KRT_MINIMAP_GUI", "CUSTOM_CLASS_COLORS"
}
