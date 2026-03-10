-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: none
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local Core = feature.Core or addon.Core

addon.DBSchema = addon.DBSchema or {}
local DBSchema = addon.DBSchema

-- ----- Internal state ----- --
local DEFAULT_RAID_SCHEMA_VERSION = 3

-- ----- Private helpers ----- --
local function normalizeSchemaVersion(value)
    local version = tonumber(value)
    if not version or version < 1 then
        return DEFAULT_RAID_SCHEMA_VERSION
    end
    return version
end

-- ----- Public methods ----- --
DBSchema.RAID_SCHEMA_VERSION = normalizeSchemaVersion(DBSchema.RAID_SCHEMA_VERSION)

function DBSchema.GetRaidSchemaVersion()
    local version = normalizeSchemaVersion(DBSchema.RAID_SCHEMA_VERSION)
    DBSchema.RAID_SCHEMA_VERSION = version
    return version
end

function Core.GetRaidSchemaVersion()
    return DBSchema.GetRaidSchemaVersion()
end
