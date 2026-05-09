-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: static raid item source data for Vanilla through WotLK
-- exports: addon.LootSourcesData

local addon = select(2, ...)

-- ----- Internal state ----- --
addon.LootSourcesData = addon.LootSourcesData or {}
addon.LootSourcesData.ByItemId = addon.LootSourcesData.ByItemId or {}

-- Icecrown Citadel - Lord Marrowgar
addon.LootSourcesData.ByItemId[50761] = {
    {
        npcId = 36612,
        npcName = "Lord Marrowgar",
        raid = "Icecrown Citadel",
        kind = "boss",
        modes = { normal10 = true },
    },
}

-- Icecrown Citadel - Deathbound Ward trash
addon.LootSourcesData.ByItemId[50452] = {
    {
        npcId = 37007,
        npcName = "Deathbound Ward",
        raid = "Icecrown Citadel",
        kind = "trash",
        modes = { normal10 = true, normal25 = true, heroic10 = true, heroic25 = true },
    },
}
