std = "lua51"

include_files = {
    "!KRT/**/*.lua",
}

exclude_files = {
    ".git",
    ".github",
    ".luarocks",
    "**/Libs/**/*.lua",
    "_dev/**",
}

globals = {
  -- WoW API core
  "CreateFrame", "DEFAULT_CHAT_FRAME", "UIParent", "SendChatMessage", "GetTime",
  "UnitName", "GetItemInfo", "PlaySound", "GameTooltip", "LibStub",
  "SlashCmdList", "RaidNotice_AddMessage", "IsInRaid", "IsInGroup",
  "GetNumRaidMembers", "GetNumPartyMembers", "GetLootRollItemInfo",
  "SetItemRef", "hooksecurefunc",

  -- Addon namespace / globals
  "KRT", "KRT_CurrentRaid", "KRT_LastBoss", "KRT_Debug",
  "KRT_Players", "KRT_Raids", "KRT_Options", "KRT_Warnings",
  "KRT_Spammer", "KRT_ExportString", "KRT_SavedReserves", "KRT_NextReset",
  "KRT_FakeTooltip", "KRT_MINIMAP_GUI", "CUSTOM_CLASS_COLORS"
}
