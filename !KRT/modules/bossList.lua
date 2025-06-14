-- modules/bossList.lua
-- This file will be loaded after KRT.lua, so KRT should be defined.
local KRT = _G["KRT"]

if not KRT then
    -- This should ideally not happen if the .toc load order is correct,
    -- but it's a good defensive check.
    error("KRT global table not found when loading bossList.lua")
end

-- Reference the boss list from LibBossIDs-1.0 instead of maintaining our own.
KRT.bossListIDs = LibStub("LibBossIDs-1.0").BossIDs

