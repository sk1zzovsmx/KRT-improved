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

local DEFAULT_RAID_SCHEMA_VERSION = 1
local version = tonumber(DBSchema.RAID_SCHEMA_VERSION)
if not version or version < 1 then
    version = DEFAULT_RAID_SCHEMA_VERSION
end
DBSchema.RAID_SCHEMA_VERSION = version

function DBSchema.GetRaidSchemaVersion()
    local out = tonumber(DBSchema.RAID_SCHEMA_VERSION)
    if not out or out < 1 then
        out = DEFAULT_RAID_SCHEMA_VERSION
        DBSchema.RAID_SCHEMA_VERSION = out
    end
    return out
end

function Core.GetRaidSchemaVersion()
    return DBSchema.GetRaidSchemaVersion()
end

