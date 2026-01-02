--[[
    KRT_SVTemplate.lua
    - SavedVariables defaults + schema migrations.
    - Keep keys stable; never overwrite user-set values.
]]

local _, addon = ...

addon.SV = addon.SV or {}
local SV = addon.SV

SV.SCHEMA_VERSION = 1

SV.defaults = {
    schemaVersion = SV.SCHEMA_VERSION,
    debug = false,

    -- Example bucket for UI-only settings
    ui = {
        scale = 1.0,
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        else
            if dst[k] == nil then dst[k] = v end
        end
    end
end

function SV:Init()
    KRT_Options = KRT_Options or {}
    KRT_Options.migrations = KRT_Options.migrations or {}
    ApplyDefaults(KRT_Options, self.defaults)
end

function SV:Migrate()
    local v = tonumber(KRT_Options.schemaVersion) or 0
    if v == self.SCHEMA_VERSION then return end

    -- Example migration pattern:
    -- if v < 1 then
    --     -- move/rename keys, etc.
    --     KRT_Options.migrations[#KRT_Options.migrations + 1] = { from = v, to = 1, at = time() }
    -- end

    KRT_Options.schemaVersion = self.SCHEMA_VERSION
end
