-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: static raid item source data for Vanilla through WotLK
-- exports: addon.LootSourcesData

local addon = select(2, ...)

-- ----- Internal state ----- --
addon.LootSourcesData = addon.LootSourcesData or {}
addon.LootSourcesData.ByItemId = addon.LootSourcesData.ByItemId or {}
