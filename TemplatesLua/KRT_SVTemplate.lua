-- =======================================================
--  KRT SavedVariables Template (defaults + migration)
-- =======================================================
local _, addon = ...

addon.SV = addon.SV or {}
local SV = addon.SV

SV.SCHEMA = 1

SV.defaults = {
  schemaVersion = SV.SCHEMA,
  debug = false,
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

function SV:Migrate()
  local v = KRT_Options.schemaVersion or 0
  if v == self.SCHEMA then return end

  -- Example migration:
  -- if v < 1 then ... end

  KRT_Options.schemaVersion = self.SCHEMA
end
