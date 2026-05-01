-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: reserves import parsing helpers
-- exports: addon.Services.Reserves._Import

local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Strings = feature.Strings

-- ----- Internal state ----- --
feature.EnsureServiceNamespace("Reserves")
local module = addon.Services.Reserves
module._Import = module._Import or {}

local Import = module._Import

-- ----- Private helpers ----- --
local function isDebugEnabled()
    return addon.hasDebug ~= nil
end

local function cleanCSVField(field)
    if not field then
        return nil
    end
    return Strings.TrimText(field:gsub('^"(.-)"$', "%1"), true)
end

local function splitCSVLine(line)
    local out, field = {}, ""
    local inQuotes = false
    local i = 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            local nextCh = line:sub(i + 1, i + 1)
            if inQuotes and nextCh == '"' then
                field = field .. '"'
                i = i + 1
            else
                inQuotes = not inQuotes
            end
        elseif ch == "," and not inQuotes then
            out[#out + 1] = field
            field = ""
        else
            field = field .. ch
        end
        i = i + 1
    end
    out[#out + 1] = field
    return out
end

local function buildHeaderMap(fields)
    local map = {}
    for i = 1, #fields do
        local key = cleanCSVField(fields[i])
        if key and key ~= "" then
            map[Strings.NormalizeLower(key)] = i
        end
    end
    if map["itemid"] and map["name"] then
        return map, true
    end
    return map, false
end

local function getField(fields, headerMap, key, fallbackIndex)
    if headerMap and headerMap[key] then
        return fields[headerMap[key]]
    end
    return fields[fallbackIndex]
end

local function readCSVField(fields, headerMap, key, fallbackIndex)
    return cleanCSVField(getField(fields, headerMap, key, fallbackIndex))
end

local function normalizeOptionalCSVField(value)
    if value == nil or value == "" then
        return nil
    end
    return value
end

local function buildParsedCSVRow(fields, headerMap)
    local itemIdStr = readCSVField(fields, headerMap, "itemid", 2)
    local source = readCSVField(fields, headerMap, "from", 3)
    local playerName = readCSVField(fields, headerMap, "name", 4)
    local className = readCSVField(fields, headerMap, "class", 5)
    local spec = readCSVField(fields, headerMap, "spec", 6)
    local note = readCSVField(fields, headerMap, "note", 7)
    local plus = readCSVField(fields, headerMap, "plus", 8)

    local itemId = tonumber(itemIdStr)
    local playerKey = Strings.NormalizeLower(playerName, true)
    if not itemId or not playerKey then
        return nil
    end

    return {
        itemId = itemId,
        player = playerName,
        playerKey = playerKey,
        source = normalizeOptionalCSVField(source),
        class = normalizeOptionalCSVField(className),
        spec = normalizeOptionalCSVField(spec),
        note = normalizeOptionalCSVField(note),
        plus = tonumber(plus) or 0,
    }
end

local function appendParsedCSVRow(rows, fields, headerMap, line, logSkipped)
    local row = buildParsedCSVRow(fields, headerMap)
    if row then
        rows[#rows + 1] = row
        return true
    end
    if logSkipped and isDebugEnabled() then
        addon:debug(Diag.D.LogSRParseSkippedLine:format(tostring(line)))
    end
    return false
end

local function parseCSVRows(csv)
    local rows = {}
    local headerMap = nil
    local firstLine = true
    local stats = {
        headerDetected = false,
        totalLines = 0,
        dataLines = 0,
        validRows = 0,
        skippedRows = 0,
    }

    for line in csv:gmatch("[^\n]+") do
        stats.totalLines = stats.totalLines + 1
        line = line:gsub("\r$", "")
        if firstLine then
            firstLine = false
            local maybeHeader = splitCSVLine(line)
            local map, isHeader = buildHeaderMap(maybeHeader)
            if isHeader then
                stats.headerDetected = true
                headerMap = map
            else
                stats.dataLines = stats.dataLines + 1
                if appendParsedCSVRow(rows, maybeHeader, headerMap, line, false) then
                    stats.validRows = stats.validRows + 1
                else
                    stats.skippedRows = stats.skippedRows + 1
                end
            end
        else
            stats.dataLines = stats.dataLines + 1
            local fields = splitCSVLine(line)
            if appendParsedCSVRow(rows, fields, headerMap, line, true) then
                stats.validRows = stats.validRows + 1
            else
                stats.skippedRows = stats.skippedRows + 1
            end
        end
    end

    return rows, stats
end

local function validatePlusRows(rows)
    local seen = {}
    for i = 1, #rows do
        local row = rows[i]
        local rec = seen[row.playerKey]
        if not rec then
            seen[row.playerKey] = { itemId = row.itemId, player = row.player, count = 1 }
        else
            rec.count = (rec.count or 1) + 1
            if rec.itemId ~= row.itemId then
                return false,
                    "CSV_WRONG_FOR_PLUS",
                    {
                        player = row.player,
                        reason = "multi_item",
                        first = rec.itemId,
                        second = row.itemId,
                        count = rec.count,
                    }
            end
            return false,
                "CSV_WRONG_FOR_PLUS",
                {
                    player = row.player,
                    reason = "duplicate",
                    itemId = row.itemId,
                    count = rec.count,
                }
        end
    end
    return true
end

local function aggregateRows(rows, allowMulti)
    local newReservesData = {}
    local byItemPerPlayer = {}

    for i = 1, #rows do
        local row = rows[i]
        local pKey = row.playerKey

        local container = newReservesData[pKey]
        if not container then
            container = {
                playerNameDisplay = row.player,
                reserves = {},
            }
            newReservesData[pKey] = container
            byItemPerPlayer[pKey] = {}
        end

        local idx = byItemPerPlayer[pKey]
        local entry = idx[row.itemId]
        if entry then
            if allowMulti then
                entry.quantity = (tonumber(entry.quantity) or 1) + 1
            else
                entry.quantity = 1
            end
            local p = tonumber(row.plus) or 0
            if p > (tonumber(entry.plus) or 0) then
                entry.plus = p
            end
        else
            entry = {
                rawID = row.itemId,
                itemLink = nil,
                itemName = nil,
                itemIcon = nil,
                quantity = 1,
                class = row.class,
                spec = row.spec,
                note = row.note,
                plus = tonumber(row.plus) or 0,
                source = row.source,
            }
            idx[row.itemId] = entry
            container.reserves[#container.reserves + 1] = entry
        end
    end

    return newReservesData
end

-- ----- Public methods ----- --
function Import.BuildParser()
    local importStrategies = {
        multi = {
            id = "multi",
            Validate = function(rows)
                return true
            end,
            Aggregate = function(rows)
                return aggregateRows(rows, true)
            end,
        },
        plus = {
            id = "plus",
            Validate = validatePlusRows,
            Aggregate = function(rows)
                return aggregateRows(rows, false)
            end,
        },
    }

    local function getImportStrategy(service, mode)
        mode = (mode == "plus" or mode == "multi") and mode or service:GetImportMode()
        return importStrategies[mode] or importStrategies.multi
    end

    local function parseImport(service, text, mode, opts)
        if type(text) ~= "string" or not text:match("%S") then
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return nil, "EMPTY"
        end

        local resolvedMode = (mode == "plus" or mode == "multi") and mode or service:GetImportMode()
        local strategy = getImportStrategy(service, resolvedMode)

        if isDebugEnabled() then
            addon:debug(Diag.D.LogReservesParseStart)
        end

        local rows, importStats = parseCSVRows(text)
        if not rows or #rows == 0 then
            addon:warn(L.WarnNoValidRows)
            return nil, "NO_ROWS"
        end

        importStats = importStats or {}
        if isDebugEnabled() then
            addon:debug(
                Diag.D.LogReservesImportRows:format(
                    tonumber(importStats.validRows) or #rows,
                    tonumber(importStats.skippedRows) or 0,
                    tostring(importStats.headerDetected),
                    tonumber(importStats.dataLines) or 0
                )
            )
        end
        if importStats.headerDetected ~= true and (tonumber(importStats.skippedRows) or 0) > 0 then
            addon:warn(L.WarnReservesHeaderHint)
        end

        local ok, errCode, errData = strategy.Validate(rows)
        if not ok then
            if isDebugEnabled() then
                addon:debug(
                    Diag.D.LogReservesImportWrongModePlus and Diag.D.LogReservesImportWrongModePlus:format(tostring(errData and errData.player))
                        or ("Wrong CSV for Plus System: " .. tostring(errData and errData.player))
                )
            end
            return nil, errCode or "CSV_INVALID", errData
        end

        local newReservesData = strategy.Aggregate(rows)
        return {
            mode = resolvedMode,
            reservesData = newReservesData,
            nPlayers = addon.tLength(newReservesData),
            opts = opts,
            importStats = importStats,
        }
    end

    return {
        ParseImport = parseImport,
    }
end
