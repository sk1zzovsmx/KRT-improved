-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local type, tonumber, tostring = type, tonumber, tostring
local strlower = string.lower

addon.Sort = addon.Sort or feature.Sort or {}
local Sort = addon.Sort

-- ----- Internal state ----- --

-- ----- Private helpers ----- --

-- ----- Public methods ----- --

function Sort.CompareValues(aValue, bValue, asc)
    if asc then
        return aValue < bValue
    end
    return aValue > bValue
end

function Sort.CompareNumbers(aValue, bValue, asc, fallback)
    local defaultValue = (fallback ~= nil) and fallback or 0
    local aNum = tonumber(aValue)
    if aNum == nil then
        aNum = defaultValue
    end
    local bNum = tonumber(bValue)
    if bNum == nil then
        bNum = defaultValue
    end
    return Sort.CompareValues(aNum, bNum, asc)
end

function Sort.CompareStrings(aValue, bValue, asc)
    return Sort.CompareValues(tostring(aValue or ""), tostring(bValue or ""), asc)
end

function Sort.GetLootSortName(itemName, itemLink, itemId)
    local name = itemName
    if (not name or name == "") and type(itemLink) == "string" then
        name = itemLink:match("|h%[(.-)%]|h")
    end
    if name and name ~= "" then
        return tostring(name)
    end
    local id = tonumber(itemId)
    if id then
        return ("Item %d"):format(id)
    end
    return "Item ?"
end

function Sort.CompareLootTie(a, b, asc)
    local aName = strlower(tostring((a and a.sortName) or ""))
    local bName = strlower(tostring((b and b.sortName) or ""))
    if aName ~= bName then
        return Sort.CompareValues(aName, bName, asc)
    end

    local aItemId = tonumber(a and a.itemId) or 0
    local bItemId = tonumber(b and b.itemId) or 0
    if aItemId ~= bItemId then
        return Sort.CompareValues(aItemId, bItemId, asc)
    end

    return Sort.CompareNumbers(a and a.id, b and b.id, asc, 0)
end
