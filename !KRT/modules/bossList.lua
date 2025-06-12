-- modules/bossList.lua
-- This file will be loaded after KRT.lua, so KRT should be defined.
local KRT = _G["KRT"]

if not KRT then
    -- This should ideally not happen if the .toc load order is correct,
    -- but it's a good defensive check.
    error("KRT global table not found when loading bossList.lua")
end

-- Populate the boss list from LibBossIDs-1.0
local lib = LibStub("LibBossIDs-1.0", true)

KRT.BossIDs = {}

if lib and lib.BossIDs then
    for id in pairs(lib.BossIDs) do
        KRT.BossIDs[id] = true
    end
end
