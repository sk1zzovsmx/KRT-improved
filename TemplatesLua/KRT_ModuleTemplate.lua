-- =======================================================
--  KRT Module Template (drop-in)
-- =======================================================
local _, addon = ...

do
  addon.ModuleName = addon.ModuleName or {}
  local M = addon.ModuleName
  local L = addon.L

  -- -----------------------------------------------------
  -- Internal state
  -- -----------------------------------------------------
  local state = {
    enabled = true,
  }

  -- -----------------------------------------------------
  -- Private helpers
  -- -----------------------------------------------------
  local function ResetState()
    -- wipe / reset module locals
  end

  -- -----------------------------------------------------
  -- Public API
  -- -----------------------------------------------------
  function M:Init()
    -- register events here (via dispatcher), set defaults
    -- addon.Events:Register("SOME_EVENT", self, "OnSomeEvent")
  end

  function M:Enable()
    state.enabled = true
  end

  function M:Disable()
    state.enabled = false
  end

  -- -----------------------------------------------------
  -- Event handlers
  -- -----------------------------------------------------
  function M:OnSomeEvent(...)
    if not state.enabled then return end
    -- logic
  end
end
