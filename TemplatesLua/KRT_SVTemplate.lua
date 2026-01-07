--[[
    KRT_SVTemplate.lua
    - SavedVariables defaults.
    - Keep keys stable; never overwrite user-set values.
]]

local _, addon = ...

addon.SV = addon.SV or {}
local SV = addon.SV
SV.defaults = {
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
    ApplyDefaults(KRT_Options, self.defaults)
end

