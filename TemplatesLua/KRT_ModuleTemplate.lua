--[[
    KRT_ModuleTemplate.lua
    - Canonical module skeleton for KRT.
    - Use this for new modules in KRT.lua or Modules/*.lua.
]]

local _, addon = ...

do
    --------------------------------------------------------------------------
    -- Module setup
    --------------------------------------------------------------------------
    addon.ModuleName = addon.ModuleName or {}
    local module = addon.ModuleName
    local L = addon.L

    --------------------------------------------------------------------------
    -- Internal state (module-local)
    --------------------------------------------------------------------------
    local state = {
        enabled = true,
    }

    --------------------------------------------------------------------------
    -- Private helpers
    --------------------------------------------------------------------------
    local function ResetState()
        -- wipe / reset module locals
    end

    --------------------------------------------------------------------------
    -- Public API
    --------------------------------------------------------------------------
    function module:Init()
        -- set defaults, wire callbacks, etc.
        -- Prefer routing WoW events through addon:* handlers in KRT.lua.
    end

    function module:Enable()
        state.enabled = true
    end

    function module:Disable()
        state.enabled = false
    end

    function module:IsEnabled()
        return state.enabled == true
    end

    --------------------------------------------------------------------------
    -- Event handlers (optional)
    --------------------------------------------------------------------------
    function module:OnSOME_EVENT(...)
        if not state.enabled then return end
        -- logic
    end
end
