-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Database.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Database.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Frames = feature.Frames
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events
local C = feature.C
local Database = feature.Database
local Options = feature.Options
local Bus = feature.Bus
local ListController = feature.ListController
local MultiSelect = feature.MultiSelect
local Strings = feature.Strings
local Colors = feature.Colors
local Base64 = feature.Base64
local Sort = feature.Sort
local IgnoredMobs = feature.IgnoredMobs
local Services = feature.Services

local NormalizeName = Strings.NormalizeName
local NormalizeLower = Strings.NormalizeLower
local TrimText = Strings.TrimText

local CompareValues = Sort.CompareValues
local CompareNumbers = Sort.CompareNumbers
local function compareStrings(aValue, bValue, asc)
    return CompareValues(tostring(aValue or ""), tostring(bValue or ""), asc)
end
local GetLootSortName = Sort.GetLootSortName

local function compareLootTie(a, b, asc)
    local aName = strlower(tostring((a and a.sortName) or ""))
    local bName = strlower(tostring((b and b.sortName) or ""))
    if aName ~= bName then
        return CompareValues(aName, bName, asc)
    end

    local aItemId = tonumber(a and a.itemId) or 0
    local bItemId = tonumber(b and b.itemId) or 0
    if aItemId ~= bItemId then
        return CompareValues(aItemId, bItemId, asc)
    end

    return CompareNumbers(a and a.id, b and b.id, asc, 0)
end

local InternalEvents = Events.Internal

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local rollTypes = feature.rollTypes
local lootTypesColored = feature.lootTypesColored
local itemColors = feature.itemColors
local showLoggerExportFrame
local setLootEntry

local _G = _G
local tinsert, tremove, twipe, tconcat = table.insert, table.remove, table.wipe, table.concat
local pairs, ipairs, type, select = pairs, ipairs, type, select

local tostring, tonumber = tostring, tonumber
local max, floor = math.max, math.floor
local strlower = string.lower
local IsTrashMobName = IgnoredMobs.IsTrashMobName
local GetTrashMobName = IgnoredMobs.GetTrashMobName

local loggerPanelNames = {
    "KRTLoggerRaids",
    "KRTLoggerBosses",
    "KRTLoggerBossAttendees",
    "KRTLoggerRaidAttendees",
    "KRTLoggerLoot",
}

local loggerHeaderSuffixes = {
    "HeaderNum",
    "HeaderDate",
    "HeaderZone",
    "HeaderSize",
    "HeaderName",
    "HeaderTime",
    "HeaderMode",
    "HeaderJoin",
    "HeaderLeave",
    "HeaderItem",
    "HeaderSource",
    "HeaderWinner",
    "HeaderType",
    "HeaderRoll",
}

local LOGGER_COMPACT_ROW_HEIGHT = 22
local LOGGER_LOOT_ROW_HEIGHT = 32

local LOGGER_LIST_WIDTH_FALLBACK = 240
local LOGGER_SCROLLBAR_GUTTER_WIDTH = 24
local LOGGER_ROW_LEFT_INSET = 3
local LOGGER_ROW_COLUMN_GAP = 6
local LOGGER_HEADER_COLUMN_GAP = LOGGER_ROW_COLUMN_GAP
local LOGGER_LOOT_NAME_LEFT_OFFSET = 34
local LOGGER_HEADER_TAB_INSET = 1
local LOGGER_PANEL_SCROLL_LEFT_OFFSET = 3
local LOGGER_HEADER_TOP_OFFSET = -25
local LOGGER_ATTENDANCE_TIME_COLUMN_MIN_WIDTH = 56

local LOGGER_LOOT_COLUMN_MIN_WIDTHS = {
    icon = 30,
    item = 165,
    source = 105,
    winner = 86,
    type = 45,
    roll = 38,
    time = 48,
}

local LOGGER_LOOT_COLUMN_RATIOS = {
    item = 0.34,
    source = 0.22,
    winner = 0.18,
    type = 0.08,
    roll = 0.07,
    time = 0.11,
}

local LOGGER_ATTENDANCE_COLUMN_MIN_WIDTHS = {
    name = 106,
    join = LOGGER_ATTENDANCE_TIME_COLUMN_MIN_WIDTH,
    leave = LOGGER_ATTENDANCE_TIME_COLUMN_MIN_WIDTH,
}

local LOGGER_ATTENDANCE_COLUMN_RATIOS = {
    name = 0.56,
    join = 0.22,
    leave = 0.22,
}

local LOGGER_BOSS_COLUMN_MIN_WIDTHS = {
    id = 28,
    name = 150,
    time = 44,
    mode = 48,
}

local LOGGER_BOSS_COLUMN_RATIOS = {
    name = 0.72,
    time = 0.13,
    mode = 0.15,
}

local function setTextureColor(texture, r, g, b, a)
    if texture and texture.SetTexture then
        texture:SetTexture(r, g, b, a)
    end
end

local function ensureLoggerHeaderTab(header)
    if not header or header._krtHeaderTab then
        return
    end

    local fill = header:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
    fill:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
    header._krtHeaderFill = fill

    local top = header:CreateTexture(nil, "BORDER")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
    top:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
    header._krtHeaderTop = top

    local bottom = header:CreateTexture(nil, "BORDER")
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
    bottom:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
    header._krtHeaderBottom = bottom

    local left = header:CreateTexture(nil, "BORDER")
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", header, "TOPLEFT", LOGGER_HEADER_TAB_INSET, -1)
    left:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", LOGGER_HEADER_TAB_INSET, 1)
    header._krtHeaderLeft = left

    local right = header:CreateTexture(nil, "BORDER")
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", header, "TOPRIGHT", -LOGGER_HEADER_TAB_INSET, -1)
    right:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -LOGGER_HEADER_TAB_INSET, 1)
    header._krtHeaderRight = right

    header._krtHeaderTab = true
end

local function styleLoggerHeader(header)
    if not header then
        return
    end

    ensureLoggerHeaderTab(header)

    local text = header.GetFontString and header:GetFontString() or nil
    if text and text.SetTextColor then
        text:SetTextColor(1.00, 0.86, 0.20)
    end
    if text and text.SetJustifyH then
        text:SetJustifyH("LEFT")
    end

    local bg = header.GetName and _G[header:GetName() .. "Bg"] or nil
    if bg and bg.SetTexture then
        bg:SetTexture(0.02, 0.02, 0.02, 0.00)
    end

    setTextureColor(header._krtHeaderFill, 0.015, 0.014, 0.012, 0.88)
    setTextureColor(header._krtHeaderTop, 0.72, 0.62, 0.38, 0.92)
    setTextureColor(header._krtHeaderBottom, 0.25, 0.22, 0.16, 0.95)
    setTextureColor(header._krtHeaderLeft, 0.38, 0.34, 0.24, 0.72)
    setTextureColor(header._krtHeaderRight, 0.38, 0.34, 0.24, 0.72)
end

local function styleLoggerPanel(frameName)
    local frame = frameName and _G[frameName] or nil
    if not frame then
        return
    end

    if frame.SetBackdropColor then
        frame:SetBackdropColor(0.01, 0.01, 0.01, 0.88)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(0.56, 0.52, 0.45, 0.95)
    end

    local title = _G[frameName .. "Title"]
    if title then
        title:SetTextColor(1.00, 0.82, 0.00)
        title:SetJustifyH("LEFT")
    end

    for i = 1, #loggerHeaderSuffixes do
        styleLoggerHeader(_G[frameName .. loggerHeaderSuffixes[i]])
    end
end

local function applyLoggerSkin()
    for i = 1, #loggerPanelNames do
        styleLoggerPanel(loggerPanelNames[i])
    end
end

local function styleLoggerRow(row)
    if not row then
        return
    end

    row._krtRowVisualStyle = "logger"
    if not row._krtLoggerBg then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        row._krtLoggerBg = bg

        local line = row:CreateTexture(nil, "BORDER")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 0)
        row._krtLoggerLine = line
    end

    if row._krtLoggerLine then
        row._krtLoggerLine:SetTexture(0.32, 0.30, 0.25, 0.42)
    end
end

local function setLoggerRowIndex(row, index)
    if not row then
        return
    end

    styleLoggerRow(row)
    local isAlt = index and index % 2 == 0
    if row._krtLoggerBg then
        if isAlt then
            row._krtLoggerBg:SetTexture(0.07, 0.07, 0.07, 0.74)
        else
            row._krtLoggerBg:SetTexture(0.025, 0.025, 0.025, 0.76)
        end
    end
end

local SetSelectedRaid
local deleteSelectedAttendees
local setFrameLabel
local setPanelTitle
local getSelectedRaidRecord
local setFrameHint
local needRaid
local needBoss
local needLoot
local runWithSelectedRaid
local resetSelections
local isLoggerViewingCurrentRaid
local requestRosterBoundListsRefresh
local selectRaid
local selectBoss
local selectBossPlayer
local selectPlayer
local selectItem
local onLootRowEnter
local onLootRowLeave
local fillBossBox
local selectionEvents = {
    selectedRaid = InternalEvents.LoggerSelectRaid,
    selectedBoss = InternalEvents.LoggerSelectBoss,
    selectedPlayer = InternalEvents.LoggerSelectPlayer,
    selectedBossPlayer = InternalEvents.LoggerSelectBossPlayer,
    selectedItem = InternalEvents.LoggerSelectItem,
}

local function triggerSelectionEvent(target, key, ...)
    local eventName = selectionEvents[key]
    if not eventName then
        return
    end
    Bus.TriggerEvent(eventName, target[key], ...)
end

local RAID_SORT_HEADERS = {
    { suffix = "HeaderNum", key = "id" },
    { suffix = "HeaderDate", key = "date" },
    { suffix = "HeaderZone", key = "zone" },
    { suffix = "HeaderSize", key = "size" },
}

local LOGGER_RAID_COLUMN_MIN_WIDTHS = {
    id = 24,
    date = 88,
    zone = 128,
    size = 36,
}

local LOGGER_RAID_COLUMN_RATIOS = {
    date = 0.20,
    zone = 0.66,
    size = 0.14,
}

local function setWidgetWidth(widget, width)
    if widget and widget.SetWidth then
        widget:SetWidth(width)
    end
end

local function setHeaderWidth(widget, width, includeTrailingGap)
    local gap = includeTrailingGap and LOGGER_HEADER_COLUMN_GAP or 0
    setWidgetWidth(widget, (tonumber(width) or 0) + gap)
end

local function positionLoggerHeader(header, frameName, offsetX, width, includeTrailingGap)
    local frame = frameName and _G[frameName] or nil
    if not (header and frame) then
        return
    end

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", offsetX, LOGGER_HEADER_TOP_OFFSET)
    setHeaderWidth(header, width, includeTrailingGap)
end

local function positionLoggerHeaderColumns(frameName, columns, startOffset)
    local offset = tonumber(startOffset) or LOGGER_PANEL_SCROLL_LEFT_OFFSET
    for i = 1, #columns do
        local column = columns[i]
        positionLoggerHeader(column.header, frameName, offset, column.width, column.trailingGap)
        offset = offset + (tonumber(column.width) or 0)
        if column.trailingGap then
            offset = offset + LOGGER_HEADER_COLUMN_GAP
        end
    end
end

local function getLoggerListContentWidth(frameName)
    if not frameName then
        return LOGGER_LIST_WIDTH_FALLBACK
    end

    local scroll = _G[frameName .. "ScrollFrame"]
    local width = scroll and scroll.GetWidth and scroll:GetWidth() or nil
    if type(width) ~= "number" or width <= 0 then
        local frame = _G[frameName]
        width = frame and frame.GetWidth and frame:GetWidth() or nil
        if type(width) == "number" and width > LOGGER_SCROLLBAR_GUTTER_WIDTH then
            width = width - LOGGER_SCROLLBAR_GUTTER_WIDTH
        end
    end

    width = tonumber(width) or LOGGER_LIST_WIDTH_FALLBACK
    return max(LOGGER_LIST_WIDTH_FALLBACK, floor(width))
end

local function getLoggerListColumnBudget(frameName, leadOffset, gapCount, returnedWidthOffset)
    local width = getLoggerListContentWidth(frameName)
    local budget = width - (tonumber(leadOffset) or 0) - ((tonumber(gapCount) or 0) * LOGGER_ROW_COLUMN_GAP)
    budget = budget + (tonumber(returnedWidthOffset) or 0)
    return max(LOGGER_LIST_WIDTH_FALLBACK, floor(budget))
end

local function calculateLoggerColumnWidths(totalWidth, minWidths, ratios, fixedKeys)
    local widths = {}
    local variableKeys = {}
    local fixed = {}
    local usedWidth = 0
    local ratioTotal = 0

    if fixedKeys then
        for i = 1, #fixedKeys do
            fixed[fixedKeys[i]] = true
        end
    end

    for key, minWidth in pairs(minWidths) do
        local width = tonumber(minWidth) or 0
        widths[key] = width
        usedWidth = usedWidth + width
        if not fixed[key] then
            variableKeys[#variableKeys + 1] = key
            ratioTotal = ratioTotal + (tonumber(ratios[key]) or 0)
        end
    end

    local extraWidth = floor((tonumber(totalWidth) or 0) - usedWidth)
    if extraWidth <= 0 or ratioTotal <= 0 then
        return widths
    end

    local allocated = 0
    for i = 1, #variableKeys do
        local key = variableKeys[i]
        local ratio = (tonumber(ratios[key]) or 0) / ratioTotal
        local addition = floor(extraWidth * ratio)
        widths[key] = widths[key] + addition
        allocated = allocated + addition
    end

    local remainder = extraWidth - allocated
    if remainder > 0 then
        for i = 1, #variableKeys do
            local key = variableKeys[i]
            widths[key] = widths[key] + 1
            remainder = remainder - 1
            if remainder <= 0 then
                break
            end
        end
    end

    return widths
end

local function getRaidColumnWidths(frameName)
    local budget = getLoggerListColumnBudget(frameName, LOGGER_ROW_LEFT_INSET, 3)
    return calculateLoggerColumnWidths(budget, LOGGER_RAID_COLUMN_MIN_WIDTHS, LOGGER_RAID_COLUMN_RATIOS, { "id" })
end

local function getLootColumnWidths(frameName)
    local budget = getLoggerListColumnBudget(frameName, LOGGER_LOOT_NAME_LEFT_OFFSET, 5, LOGGER_LOOT_COLUMN_MIN_WIDTHS.icon)
    return calculateLoggerColumnWidths(budget, LOGGER_LOOT_COLUMN_MIN_WIDTHS, LOGGER_LOOT_COLUMN_RATIOS, { "icon" })
end

local function getAttendanceColumnWidths(frameName)
    local budget = getLoggerListColumnBudget(frameName, LOGGER_ROW_LEFT_INSET, 2)
    return calculateLoggerColumnWidths(budget, LOGGER_ATTENDANCE_COLUMN_MIN_WIDTHS, LOGGER_ATTENDANCE_COLUMN_RATIOS)
end

local function getBossColumnWidths(frameName)
    local budget = getLoggerListColumnBudget(frameName, LOGGER_ROW_LEFT_INSET, 3)
    return calculateLoggerColumnWidths(budget, LOGGER_BOSS_COLUMN_MIN_WIDTHS, LOGGER_BOSS_COLUMN_RATIOS, { "id" })
end

local function applyRaidListColumnWidths(frameName)
    if not frameName then
        return
    end
    local widths = getRaidColumnWidths(frameName)
    positionLoggerHeaderColumns(frameName, {
        { header = _G[frameName .. "HeaderNum"], width = widths.id, trailingGap = true },
        { header = _G[frameName .. "HeaderDate"], width = widths.date, trailingGap = true },
        { header = _G[frameName .. "HeaderZone"], width = widths.zone, trailingGap = true },
        { header = _G[frameName .. "HeaderSize"], width = widths.size, trailingGap = false },
    }, LOGGER_PANEL_SCROLL_LEFT_OFFSET + LOGGER_ROW_LEFT_INSET)
end

local function applyRaidRowColumnWidths(ui, frameName)
    if not ui then
        return
    end
    local widths = getRaidColumnWidths(frameName)
    setWidgetWidth(ui.ID, widths.id)
    setWidgetWidth(ui.Date, widths.date)
    setWidgetWidth(ui.Zone, widths.zone)
    setWidgetWidth(ui.Size, widths.size)
end

local function applyLootListColumnWidths(frameName)
    if not frameName then
        return
    end
    local widths = getLootColumnWidths(frameName)
    positionLoggerHeaderColumns(frameName, {
        { header = _G[frameName .. "HeaderItem"], width = widths.icon + widths.item, trailingGap = true },
        { header = _G[frameName .. "HeaderSource"], width = widths.source, trailingGap = true },
        { header = _G[frameName .. "HeaderWinner"], width = widths.winner, trailingGap = true },
        { header = _G[frameName .. "HeaderType"], width = widths.type, trailingGap = true },
        { header = _G[frameName .. "HeaderRoll"], width = widths.roll, trailingGap = true },
        { header = _G[frameName .. "HeaderTime"], width = widths.time, trailingGap = false },
    }, LOGGER_PANEL_SCROLL_LEFT_OFFSET)
end

local function applyLootRowColumnWidths(ui, frameName)
    if not ui then
        return
    end
    local widths = getLootColumnWidths(frameName)
    setWidgetWidth(ui.Name, widths.item)
    setWidgetWidth(ui.Source, widths.source)
    setWidgetWidth(ui.Winner, widths.winner)
    setWidgetWidth(ui.Type, widths.type)
    setWidgetWidth(ui.Roll, widths.roll)
    setWidgetWidth(ui.Time, widths.time)
end

local function applyAttendanceListColumnWidths(frameName)
    if not frameName then
        return
    end
    local widths = getAttendanceColumnWidths(frameName)
    positionLoggerHeaderColumns(frameName, {
        { header = _G[frameName .. "HeaderName"], width = widths.name, trailingGap = true },
        { header = _G[frameName .. "HeaderJoin"], width = widths.join, trailingGap = true },
        { header = _G[frameName .. "HeaderLeave"], width = widths.leave, trailingGap = false },
    }, LOGGER_PANEL_SCROLL_LEFT_OFFSET + LOGGER_ROW_LEFT_INSET)
end

local function applyAttendanceRowColumnWidths(ui, frameName)
    if not ui then
        return
    end
    local widths = getAttendanceColumnWidths(frameName)
    setWidgetWidth(ui.Name, widths.name)
    setWidgetWidth(ui.Join, widths.join)
    setWidgetWidth(ui.Leave, widths.leave)
end

local function applyBossListColumnWidths(frameName)
    if not frameName then
        return
    end
    local widths = getBossColumnWidths(frameName)
    positionLoggerHeaderColumns(frameName, {
        { header = _G[frameName .. "HeaderNum"], width = widths.id, trailingGap = true },
        { header = _G[frameName .. "HeaderName"], width = widths.name, trailingGap = true },
        { header = _G[frameName .. "HeaderTime"], width = widths.time, trailingGap = true },
        { header = _G[frameName .. "HeaderMode"], width = widths.mode, trailingGap = false },
    }, LOGGER_PANEL_SCROLL_LEFT_OFFSET + LOGGER_ROW_LEFT_INSET)
end

local function applyBossRowColumnWidths(ui, frameName)
    if not ui then
        return
    end
    local widths = getBossColumnWidths(frameName)
    setWidgetWidth(ui.ID, widths.id)
    setWidgetWidth(ui.Name, widths.name)
    setWidgetWidth(ui.Time, widths.time)
    setWidgetWidth(ui.Mode, widths.mode)
end

local function bindRaidSortHeaders(frameName, listRef)
    local frame = frameName and _G[frameName] or nil
    if not frame or frame._krtBound then
        return
    end

    for i = 1, #RAID_SORT_HEADERS do
        local header = RAID_SORT_HEADERS[i]
        local sortKey = header.key
        local headerButton = _G[frameName .. header.suffix]
        if headerButton then
            Frames.SetScriptSafely(headerButton, "OnClick", function()
                listRef:Sort(sortKey)
            end)
        end
    end

    frame._krtBound = true
end

local function buildRaidListRow(raid, seq, queries)
    if not raid then
        return nil
    end

    local summary = queries and queries.GetRaidSummary and queries:GetRaidSummary(raid) or nil
    local row = {}
    row.id = tonumber(raid.raidNid)
    row.seq = seq
    row.zone = raid.zone
    row.size = (summary and summary.size) or raid.size
    row.difficulty = tonumber((summary and summary.difficulty) or raid.difficulty)
    local mode = row.difficulty and ((row.difficulty == 3 or row.difficulty == 4) and "H" or "N") or "?"
    row.sizeLabel = tostring(row.size or "") .. mode
    row.date = (summary and summary.startTime) or raid.startTime
    row.dateFmt = date("%d/%m/%y %H:%M", row.date)
    return row
end

local function fillRaidListData(out, contextTag)
    local raidStore = Database.GetRaidStoreOrNil(contextTag, { "GetAllRaids", "GetRaidByIndex" })
    local raids = raidStore and raidStore:GetAllRaids() or {}
    local queries = Database.GetRaidQueries and Database.GetRaidQueries() or nil
    for i = 1, #raids do
        local raid = raidStore and raidStore:GetRaidByIndex(i) or Database.EnsureRaidById(i)
        local row = buildRaidListRow(raid, i, queries)
        if row then
            out[i] = row
        end
    end
end

addon.Controllers.Logger = addon.Controllers.Logger or {}
local module = addon.Controllers.Logger
module._ui = UIScaffold.EnsureModuleUi(module)

local function getCountTitle(baseText, count)
    return ("%s (%d)"):format(tostring(baseText or ""), tonumber(count) or 0)
end

local function getContextTitle(baseText, contextText, emptyHint)
    local suffix = contextText
    if not suffix or suffix == "" then
        suffix = emptyHint
    end
    if suffix and suffix ~= "" then
        return ("%s - %s"):format(baseText, suffix)
    end
    return baseText
end

local function getCountContextTitle(baseText, count, contextText, emptyHint)
    return getContextTitle(getCountTitle(baseText, count), contextText, emptyHint)
end

local function getRaidContextLabel(selectedRaid)
    if not selectedRaid then
        return nil
    end
    local store = module.Store
    local view = module.View
    local raid = store and store:GetRaid(selectedRaid) or nil
    if not raid then
        return nil
    end
    local zone = raid.zone or nil
    local difficulty = view and view:GetRaidDifficultyLabel(raid) or ""
    if zone and zone ~= "" and difficulty ~= "" then
        return ("%s %s"):format(zone, difficulty)
    end
    if zone and zone ~= "" then
        return zone
    end
    if difficulty ~= "" then
        return difficulty
    end
    return nil
end

local function getBossContextLabel(selectedRaid, selectedBoss)
    if not (selectedRaid and selectedBoss) then
        return nil
    end
    local store = module.Store
    local view = module.View
    local raid = store and store:GetRaid(selectedRaid) or nil
    local boss = raid and store:GetBoss(raid, selectedBoss) or nil
    if not boss then
        return nil
    end
    local name = boss.name
    if not name or name == "" then
        name = L.StrTrashMob
    end
    local mode = view and view:GetBossModeLabel(boss) or nil
    if mode and mode ~= "" then
        return ("%s %s"):format(name, mode)
    end
    return name
end

local function getPlayerContextLabel(selectedRaid, playerNid)
    if not (selectedRaid and playerNid) then
        return nil
    end
    local store = module.Store
    local raid = store and store:GetRaid(selectedRaid) or nil
    local player = raid and store:GetPlayer(raid, playerNid) or nil
    if player and player.name and player.name ~= "" then
        return L.StrLoggerLabelPlayer:format(player.name)
    end
    return nil
end

local function getLootPanelContextLabel(sel)
    local parts = {}
    local bossLabel = getBossContextLabel(sel.selectedRaid, sel.selectedBoss)
    local playerLabel = getPlayerContextLabel(sel.selectedRaid, sel.selectedBossPlayer or sel.selectedPlayer)

    if bossLabel and bossLabel ~= "" then
        parts[#parts + 1] = bossLabel
    end
    if playerLabel and playerLabel ~= "" then
        parts[#parts + 1] = playerLabel
    end
    if #parts > 0 then
        return tconcat(parts, " | ")
    end
    return getRaidContextLabel(sel.selectedRaid)
end

local function getBossEmptyStateText(count, selectedRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyBossesSelectRaid
    end
    return L.StrLoggerEmptyBosses
end

local function getBossAttendeesEmptyStateText(count, selectedRaid, selectedBoss)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyBossAttendeesSelectRaid
    end
    if not selectedBoss then
        return L.StrLoggerEmptyBossAttendeesSelectBoss
    end
    return L.StrLoggerEmptyBossAttendees
end

local function getRaidAttendeesEmptyStateText(count, selectedRaid)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not selectedRaid then
        return L.StrLoggerEmptyRaidAttendeesSelectRaid
    end
    return L.StrLoggerEmptyRaidAttendees
end

local function getLootEmptyStateText(count, sel)
    if (tonumber(count) or 0) > 0 then
        return nil
    end
    if not sel.selectedRaid then
        return L.StrLoggerEmptyLootSelectRaid
    end
    if sel.selectedBoss or sel.selectedBossPlayer or sel.selectedPlayer then
        return L.StrLoggerEmptyLootFiltered
    end
    return L.StrLoggerEmptyLoot
end

local function isValidRollValue(text)
    local value = text and tonumber(text)
    if not value or value < 0 then
        return false
    end
    return true, value
end

-- Timer ownership: refresh debounce for roster-bound lists.
addon.Timer.BindMixin(module, "Logger")

-- Logger frame module.
do
    -- ----- Internal state ----- --
    local UI = module._ui
    local getFrame = makeModuleFrameGetter(module, "KRTLogger")
    -- Import service modules (extracted to Services/Logger/).
    local LoggerSvc = addon.Services.Logger
    local Store = LoggerSvc.Store
    local View = LoggerSvc.View
    local Export = LoggerSvc.Export
    local Actions = LoggerSvc.Actions

    module.Store = Store
    module.View = View
    module.Export = Export
    module.Actions = Actions

    -- Bind controller reference so Logger actions can validate selections.
    Actions:BindController(module, triggerSelectionEvent)

    -- ----- Private helpers ----- --

    function UI.AcquireRefs(frame)
        return {
            historyTabBtn = Frames.GetRef(frame, "Tab1"),
            attendanceTabBtn = Frames.GetRef(frame, "Tab2"),
            history = Frames.GetRef(frame, "History"),
            raids = Frames.GetRef(frame, "KRTLoggerRaids"),
            bosses = Frames.GetRef(frame, "KRTLoggerBosses"),
            loot = Frames.GetRef(frame, "KRTLoggerLoot"),
            raidAttendees = Frames.GetRef(frame, "KRTLoggerRaidAttendees"),
            bossAttendees = Frames.GetRef(frame, "KRTLoggerBossAttendees"),
            bossBox = Frames.GetRef(frame, "KRTLoggerBossBox"),
            attendeesBox = Frames.GetRef(frame, "KRTLoggerPlayerBox"),
        }
    end

    local function ensureSubmoduleOnLoad(moduleRef, frame)
        if not (moduleRef and frame) then
            return
        end
        if frame._krtOnLoadBound then
            return
        end
        if moduleRef._LoadFrame then
            moduleRef._LoadFrame(frame)
        elseif moduleRef.OnLoad then
            moduleRef:OnLoad(frame)
        else
            return
        end
        frame._krtOnLoadBound = true
    end

    local function clearSelection(target, key, multiSelectCtx)
        target[key] = nil
        if multiSelectCtx then
            MultiSelect.EnsureState(multiSelectCtx)
        end
    end

    setFrameLabel = function(frameName, suffix, text)
        local label = frameName and _G[frameName .. suffix] or nil
        if not label then
            return nil
        end
        if label.GetText and label:GetText() == text then
            return label
        end
        label:SetText(text)
        return label
    end

    setPanelTitle = function(frameName, text)
        setFrameLabel(frameName, "Title", text)
    end

    setFrameHint = function(frameName, suffix, text)
        local label = setFrameLabel(frameName, suffix, text or "")
        if label then
            UIPrimitives.ShowHide(label, type(text) == "string" and text ~= "")
        end
    end

    getSelectedRaidRecord = function()
        if not module.selectedRaid then
            return nil
        end
        return Store:GetRaid(module.selectedRaid)
    end

    local function applyFocusedMultiSelect(opts)
        if not opts then
            return nil, 0
        end

        local id = opts.id
        local ctx = opts.context
        if not (id and ctx and opts.setFocus) then
            return nil, 0
        end

        local function setFocusFromSelected(selectedId)
            if opts.mapSelectedToFocus then
                opts.setFocus(opts.mapSelectedToFocus(selectedId))
                return
            end
            opts.setFocus(selectedId)
        end

        if opts.isRange then
            local action, count = MultiSelect.SelectRange(ctx, opts.ordered, id, opts.isMulti)
            setFocusFromSelected(id)
            return action, count
        end

        local allowDeselect = opts.allowDeselect
        if allowDeselect == nil then
            allowDeselect = true
        end

        local action, count = MultiSelect.Toggle(ctx, id, opts.isMulti, allowDeselect)
        if action == "SINGLE_DESELECT" then
            opts.setFocus(nil)
        elseif action == "TOGGLE_OFF" then
            local clickedWasFocused = false
            if opts.isClickedFocused then
                clickedWasFocused = opts.isClickedFocused(id) and true or false
            elseif opts.getFocus then
                clickedWasFocused = (opts.getFocus() == id)
            end

            if clickedWasFocused then
                local selected = MultiSelect.GetSelected(ctx)
                setFocusFromSelected(selected[1])
            end
        else
            setFocusFromSelected(id)
        end

        if (tonumber(count) or 0) > 0 then
            MultiSelect.SetAnchor(ctx, id)
        else
            MultiSelect.SetAnchor(ctx, nil)
        end

        return action, count
    end

    local function applyModuleFocusedMultiSelect(id, context, ordered, isMulti, isRange, focusKey)
        return applyFocusedMultiSelect({
            id = id,
            context = context,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            getFocus = function()
                return module[focusKey]
            end,
            setFocus = function(value)
                module[focusKey] = value
            end,
        })
    end

    -- ----- Public methods ----- --

    module.selectedRaid = nil
    module.selectedBoss = nil
    module.selectedPlayer = nil
    module.selectedBossPlayer = nil
    module.selectedItem = nil
    module.activeTab = module.activeTab or "loot"
    SetSelectedRaid = function(raidId)
        if raidId == nil then
            module.selectedRaid = nil
        else
            module.selectedRaid = tonumber(raidId) or raidId
        end
        local state = addon.State
        state.selectedRaid = module.selectedRaid
        return module.selectedRaid
    end

    -- Multi-select context keys (runtime-only)
    -- NOTE: selection state lives in MultiSelect module and is keyed by these context strings.
    module._msRaidCtx = module._msRaidCtx or "LoggerRaids"
    module._msBossCtx = module._msBossCtx or "LoggerBosses"
    module._msBossAttCtx = module._msBossAttCtx or "LoggerBossAttendees"
    module._msRaidAttCtx = module._msRaidAttCtx or "LoggerRaidAttendees"
    module._msLootCtx = module._msLootCtx or "LoggerLoot"

    local MS_CTX_RAID = module._msRaidCtx
    local MS_CTX_BOSS = module._msBossCtx
    local MS_CTX_BOSSATT = module._msBossAttCtx
    local MS_CTX_RAIDATT = module._msRaidAttCtx
    local MS_CTX_LOOT = module._msLootCtx

    -- Multi-select modifier scopes (input policy by panel/list)
    module._msRaidScopeHistory = module._msRaidScopeHistory or "LoggerRaidsHistory"
    module._msBossScope = module._msBossScope or "LoggerBosses"
    module._msBossAttScope = module._msBossAttScope or "LoggerBossAttendees"
    module._msRaidAttScope = module._msRaidAttScope or "LoggerRaidAttendees"
    module._msLootScope = module._msLootScope or "LoggerLoot"

    local MS_SCOPE_RAID_HISTORY = module._msRaidScopeHistory
    local MS_SCOPE_BOSS = module._msBossScope
    local MS_SCOPE_BOSSATT = module._msBossAttScope
    local MS_SCOPE_RAIDATT = module._msRaidAttScope
    local MS_SCOPE_LOOT = module._msLootScope

    MultiSelect.SetModifierPolicy(MS_SCOPE_RAID_HISTORY, { allowMulti = true, allowRange = true })
    MultiSelect.SetModifierPolicy(MS_SCOPE_BOSS, { allowMulti = true, allowRange = true })
    MultiSelect.SetModifierPolicy(MS_SCOPE_BOSSATT, { allowMulti = true, allowRange = true })
    MultiSelect.SetModifierPolicy(MS_SCOPE_RAIDATT, { allowMulti = true, allowRange = true })
    MultiSelect.SetModifierPolicy(MS_SCOPE_LOOT, { allowMulti = true, allowRange = true })

    -- Clears selections that depend on the currently focused raid (boss/player/loot panels).
    -- Intentionally does NOT clear the raid selection itself.
    local function clearSelections()
        clearSelection(module, "selectedBoss", MS_CTX_BOSS)
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
        clearSelection(module, "selectedItem", MS_CTX_LOOT)
    end

    local function setPanelVisible(frame, visible)
        if not frame then
            return
        end
        UIPrimitives.ShowHide(frame, visible)
    end

    local function placePanel(frame, point, relativeTo, relativePoint, x, y, width, height)
        if not frame then
            return
        end
        if frame.ClearAllPoints then
            frame:ClearAllPoints()
        end
        if frame.SetPoint then
            frame:SetPoint(point, relativeTo, relativePoint, x, y)
        end
        if frame.SetSize then
            frame:SetSize(width, height)
        elseif frame.SetWidth and frame.SetHeight then
            frame:SetWidth(width)
            frame:SetHeight(height)
        end
    end

    local function refreshLoggerTabLayout()
        local refs = module.refs or {}
        local activeTab = module.activeTab or "loot"
        local isLootTab = activeTab == "loot"
        local isAttendanceTab = activeTab == "attendance"
        local history = refs.history

        setPanelVisible(refs.raids, true)
        setPanelVisible(refs.loot, isLootTab)
        setPanelVisible(refs.raidAttendees, isAttendanceTab)
        setPanelVisible(refs.bosses, isAttendanceTab)
        setPanelVisible(refs.bossAttendees, false)

        if isLootTab then
            placePanel(refs.raids, "TOPLEFT", history, "TOPLEFT", 0, 0, 335, 430)
            placePanel(refs.loot, "TOPLEFT", refs.raids, "TOPRIGHT", 7, 0, 600, 430)
        else
            placePanel(refs.raids, "TOPLEFT", history, "TOPLEFT", 0, 0, 335, 430)
            placePanel(refs.raidAttendees, "TOPLEFT", refs.raids, "TOPRIGHT", 7, 0, 265, 430)
            placePanel(refs.bosses, "TOPLEFT", refs.raidAttendees, "TOPRIGHT", 7, 0, 335, 430)
        end
        applyRaidListColumnWidths("KRTLoggerRaids")
        applyLootListColumnWidths("KRTLoggerLoot")
        applyAttendanceListColumnWidths("KRTLoggerRaidAttendees")
        applyBossListColumnWidths("KRTLoggerBosses")

        if refs.historyTabBtn and refs.historyTabBtn.SetText then
            refs.historyTabBtn:SetText(L.StrLootTab)
        end
        if refs.attendanceTabBtn and refs.attendanceTabBtn.SetText then
            refs.attendanceTabBtn:SetText(L.StrAttendanceTab)
        end
        if PanelTemplates_SetTab then
            PanelTemplates_SetTab(getFrame(), isLootTab and 1 or 2)
        end
    end

    local function setActiveLoggerTab(tabName)
        module.activeTab = tabName == "attendance" and "attendance" or "loot"
        if module.activeTab == "loot" then
            clearSelection(module, "selectedBoss", MS_CTX_BOSS)
            clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
            clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)
        else
            clearSelection(module, "selectedBoss", MS_CTX_BOSS)
            clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
        end
        refreshLoggerTabLayout()
        triggerSelectionEvent(module, "selectedBoss")
        triggerSelectionEvent(module, "selectedBossPlayer")
        triggerSelectionEvent(module, "selectedPlayer")
        triggerSelectionEvent(module, "selectedItem")
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    deleteSelectedAttendees = function(ctx, deleteFn, onRemoved)
        runWithSelectedRaid(function(_, rID)
            local ids = MultiSelect.GetSelected(ctx)
            if not (ids and #ids > 0) then
                return
            end

            local removed = deleteFn(rID, ids)
            if not removed or removed <= 0 then
                return
            end

            MultiSelect.EnsureState(ctx)
            if type(onRemoved) == "function" then
                onRemoved(removed, ids)
            end
        end)
    end

    local rosterUiRefreshDebounceSeconds = 0.25

    isLoggerViewingCurrentRaid = function()
        local frame = module.frame or getFrame()
        if not (frame and frame.IsShown and frame:IsShown()) then
            return false
        end
        local currentRaid = Database.GetCurrentRaid()
        return currentRaid and module.selectedRaid and tonumber(module.selectedRaid) == tonumber(currentRaid)
    end

    local function refreshRosterBoundLists()
        local listModules = { module.RaidAttendees, module.BossAttendees, module.Boss, module.Loot }
        for i = 1, #listModules do
            local ctrl = listModules[i] and listModules[i]._ctrl
            if ctrl and ctrl.Dirty then
                ctrl:Dirty()
            end
        end
    end

    requestRosterBoundListsRefresh = function()
        if module._rosterUiHandle then
            module:CancelTimer(module._rosterUiHandle)
            module._rosterUiHandle = nil
        end
        module._rosterUiHandle = module:ScheduleTimer(function()
            module._rosterUiHandle = nil
            if not isLoggerViewingCurrentRaid() then
                return
            end
            refreshRosterBoundLists()
        end, rosterUiRefreshDebounceSeconds)
    end

    -- Logger helpers: resolve current raid/boss/loot and run raid actions with a single refresh.
    needRaid = function()
        local rID = module.selectedRaid
        local raid = rID and Store:GetRaid(rID) or nil
        return raid, rID
    end

    needBoss = function(raid)
        raid = raid or (select(1, needRaid()))
        if not raid then
            return nil
        end
        local bNid = module.selectedBoss
        if not bNid then
            return nil
        end
        return Store:GetBoss(raid, bNid)
    end

    needLoot = function(raid)
        raid = raid or (select(1, needRaid()))
        if not raid then
            return nil
        end
        local lNid = module.selectedItem
        if not lNid then
            return nil
        end
        return Store:GetLoot(raid, lNid)
    end

    runWithSelectedRaid = function(fn, refreshEvent)
        local raid, rID = needRaid()
        if not raid then
            return
        end
        fn(raid, rID)
        if refreshEvent ~= false then
            Bus.TriggerEvent(refreshEvent or InternalEvents.LoggerSelectRaid, module.selectedRaid)
        end
    end

    local function getExportFrameRefs()
        local frame = Frames.Get("KRTLoggerExportFrame")
        if not frame then
            return nil
        end

        return {
            frame = frame,
            hint = Frames.GetRef(frame, "Hint"),
            lootBtn = Frames.GetRef(frame, "LootBtn"),
            raidAttendanceBtn = Frames.GetRef(frame, "RaidAttendanceBtn"),
            output = Frames.GetRef(frame, "Output"),
            outputScroll = Frames.GetRef(frame, "OutputScroll"),
            closeBtn = Frames.GetRef(frame, "CloseBtn"),
        }
    end

    local function setExportModeButtonState(refs, mode)
        local buttons = {
            { button = refs and refs.lootBtn, mode = "loot" },
            { button = refs and refs.raidAttendanceBtn, mode = "raidAttendance" },
        }

        for i = 1, #buttons do
            local entry = buttons[i]
            local button = entry.button
            if button then
                if entry.mode == mode then
                    if button.LockHighlight then
                        button:LockHighlight()
                    end
                elseif button.UnlockHighlight then
                    button:UnlockHighlight()
                end
            end
        end
    end

    local function getExportContext()
        return {
            raidId = module.selectedRaid,
            selectedBossNid = module.selectedBoss,
            selectedPlayerNid = module.selectedBossPlayer or module.selectedPlayer,
        }
    end

    local function setExportText(refs, text)
        local output = refs and refs.output
        if not output then
            return
        end

        if output.SetTextInsets then
            output:SetTextInsets(8, 8, 8, 8)
        end
        if output.SetJustifyH then
            output:SetJustifyH("LEFT")
        end
        if output.SetJustifyV then
            output:SetJustifyV("TOP")
        end
        module._lastExportCSV = text or ""
        output:SetText(module._lastExportCSV)
        output:SetCursorPosition(0)
        output:HighlightText()
        if output.SetFocus then
            output:SetFocus()
        end

        local scroll = refs.outputScroll
        if scroll and scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        if scroll and scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(0)
        end
    end

    local function adjustExportScrollBar(refs)
        local scroll = refs and refs.outputScroll
        if not (scroll and scroll.GetName) then
            return
        end

        local scrollName = scroll:GetName()
        local scrollBar = scroll.ScrollBar or _G[scrollName .. "ScrollBar"]
        if not scrollBar then
            return
        end

        local upButton = _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downButton = _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upButton then
            upButton:ClearAllPoints()
            upButton:SetPoint("TOP", scroll, "TOPRIGHT", 10, -4)
        end
        if downButton then
            downButton:ClearAllPoints()
            downButton:SetPoint("BOTTOM", scroll, "BOTTOMRIGHT", 10, 8)
        end

        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOP", scroll, "TOPRIGHT", 10, -20)
        scrollBar:SetPoint("BOTTOM", scroll, "BOTTOMRIGHT", 10, 24)
    end

    local function refreshExportFrame(mode)
        local refs = getExportFrameRefs()
        if not refs then
            return false
        end

        local raid = needRaid()
        if not raid then
            addon:error(L.ErrLoggerInvalidRaid)
            return false
        end

        mode = mode or module._loggerExportMode or "loot"
        module._loggerExportMode = mode

        local csv, errCode = Export:GetCSV(mode, raid, getExportContext())
        if errCode then
            addon:error((L.ErrLoggerExportFailed):format(tostring(errCode)))
            return false
        end

        setExportModeButtonState(refs, mode)
        adjustExportScrollBar(refs)
        setExportText(refs, csv)
        return true
    end

    local function bindExportFrame()
        local refs = getExportFrameRefs()
        if not refs or refs.frame._krtBound then
            return refs
        end

        Frames.SetFrameTitle(refs.frame, L.StrLoggerExportTitle)
        Frames.EnableDrag(refs.frame)

        if refs.hint then
            refs.hint:SetText(L.StrLoggerExportHint)
        end
        if refs.lootBtn then
            refs.lootBtn:SetText(L.BtnLoggerExportLootCSV)
            Frames.SetScriptSafely(refs.lootBtn, "OnClick", function()
                refreshExportFrame("loot")
            end)
        end
        if refs.raidAttendanceBtn then
            refs.raidAttendanceBtn:SetText(L.BtnLoggerExportRaidAttendanceCSV)
            Frames.SetScriptSafely(refs.raidAttendanceBtn, "OnClick", function()
                refreshExportFrame("raidAttendance")
            end)
        end
        if refs.output and refs.output.SetTextInsets then
            refs.output:SetTextInsets(8, 8, 8, 8)
        end
        if refs.output and refs.output.SetWordWrap then
            refs.output:SetWordWrap(true)
        end
        if refs.output then
            Frames.SetScriptSafely(refs.output, "OnTextChanged", function(self, userInput)
                if userInput then
                    self:SetText(module._lastExportCSV or "")
                    self:SetCursorPosition(0)
                    self:HighlightText()
                end
            end)
        end
        adjustExportScrollBar(refs)
        if refs.closeBtn then
            refs.closeBtn:SetText(L.BtnClose)
            Frames.SetScriptSafely(refs.closeBtn, "OnClick", function()
                refs.frame:Hide()
            end)
        end

        refs.frame._krtBound = true
        return refs
    end

    showLoggerExportFrame = function()
        local raid = needRaid()
        if not raid then
            addon:error(L.ErrLoggerInvalidRaid)
            return false
        end

        local refs = bindExportFrame()
        if not (refs and refs.frame) then
            return false
        end

        module._loggerExportMode = "loot"
        if not refreshExportFrame(module._loggerExportMode) then
            return false
        end
        refs.frame:Show()
        return true
    end

    resetSelections = function()
        clearSelections()
    end

    local function loadLoggerFrame(frame)
        UI.FrameName = Frames.BindModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                if not module.selectedRaid then
                    SetSelectedRaid(Database.GetCurrentRaid())
                end
                clearSelections()
                refreshLoggerTabLayout()
                triggerSelectionEvent(module, "selectedRaid", "ui")
            end,
            hookOnHide = function()
                SetSelectedRaid(Database.GetCurrentRaid())
                clearSelections()
            end,
        }) or UI.FrameName
        UI.Loaded = UI.FrameName ~= nil
        if not UI.Loaded then
            return
        end
        Frames.SetFrameTitle(UI.FrameName, L.StrLootLogger)
    end

    local function refreshLoggerFrame()
        local frame = getFrame()
        if not frame then
            return
        end
        if not module.selectedRaid then
            SetSelectedRaid(Database.GetCurrentRaid())
        end
        clearSelections()
        refreshLoggerTabLayout()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    local function BindHandlers(_, frame, refs)
        if refs.historyTabBtn then
            if refs.historyTabBtn.SetID then
                refs.historyTabBtn:SetID(1)
            end
            refs.historyTabBtn:SetText(L.StrLootTab)
            Frames.SetScriptSafely(refs.historyTabBtn, "OnClick", function()
                setActiveLoggerTab("loot")
            end)
        end
        if refs.attendanceTabBtn then
            if refs.attendanceTabBtn.SetID then
                refs.attendanceTabBtn:SetID(2)
            end
            refs.attendanceTabBtn:SetText(L.StrAttendanceTab)
            Frames.SetScriptSafely(refs.attendanceTabBtn, "OnClick", function()
                setActiveLoggerTab("attendance")
            end)
        end
        if PanelTemplates_SetNumTabs then
            PanelTemplates_SetNumTabs(frame, 2)
        end

        local onLoadPairs = {
            { moduleRef = module.Raids, frameRef = refs.raids },
            { moduleRef = module.Boss, frameRef = refs.bosses },
            { moduleRef = module.Loot, frameRef = refs.loot },
            { moduleRef = module.RaidAttendees, frameRef = refs.raidAttendees },
            { moduleRef = module.BossAttendees, frameRef = refs.bossAttendees },
            { moduleRef = module.BossBox, frameRef = refs.bossBox },
            { moduleRef = module.AttendeesBox, frameRef = refs.attendeesBox },
        }
        for i = 1, #onLoadPairs do
            local pair = onLoadPairs[i]
            ensureSubmoduleOnLoad(pair.moduleRef, pair.frameRef)
        end
        applyLoggerSkin()
        refreshLoggerTabLayout()
    end

    local function OnLoadFrame(frame)
        loadLoggerFrame(frame)
        return UI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        onLoad = OnLoadFrame,
        refresh = function()
            refreshLoggerFrame()
        end,
    })

    -- Selectors
    selectRaid = function(btn, button, opts)
        if button and button ~= "LeftButton" then
            return
        end
        local raidNid = btn and btn.GetID and btn:GetID()
        if not raidNid then
            return
        end
        local raidIndex = raidNid and Database.GetRaidIdByNid(raidNid) or nil
        if not raidIndex then
            return
        end

        local modifierScope = (opts and opts.modifierScope) or module._msRaidScopeHistory or MS_SCOPE_RAID_HISTORY
        local isMulti, isRange = MultiSelect.ResolveModifiers(modifierScope, opts)
        local prevFocus = module.selectedRaid

        local ordered = opts and opts.ordered or nil
        if not ordered then
            ordered = module.Raids and module.Raids._ctrl and module.Raids._ctrl.data or nil
        end
        local action, count = applyFocusedMultiSelect({
            id = raidNid,
            context = (opts and opts.context) or MS_CTX_RAID,
            ordered = ordered,
            isMulti = isMulti,
            isRange = isRange,
            allowDeselect = opts and opts.allowDeselect,
            setFocus = SetSelectedRaid,
            mapSelectedToFocus = function(nid)
                return nid and Database.GetRaidIdByNid(nid) or nil
            end,
            isClickedFocused = function(clickedNid)
                local selectedRaidNid = module.selectedRaid and Database.GetRaidNidById(module.selectedRaid) or nil
                return selectedRaidNid == clickedNid
            end,
        })

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickRaid):format(
                    tostring(raidNid),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedRaid)
                )
            )
        end

        -- If the focused raid changed, reset dependent selections (boss/player/loot panels).
        if prevFocus ~= module.selectedRaid then
            clearSelections()
        end

        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    selectBoss = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.ResolveModifiers(MS_SCOPE_BOSS)
        local prevFocus = module.selectedBoss

        local ordered = module.Boss and module.Boss._ctrl and module.Boss._ctrl.data or nil
        local action, count = applyModuleFocusedMultiSelect(id, MS_CTX_BOSS, ordered, isMulti, isRange, "selectedBoss")

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickBoss):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedBoss)
                )
            )
        end

        -- If the focused boss changed, reset boss-attendees + loot selection (filters changed).
        if prevFocus ~= module.selectedBoss then
            clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
            triggerSelectionEvent(module, "selectedBossPlayer")
        end

        triggerSelectionEvent(module, "selectedBoss")
    end

    -- Player filter: only one active at a time
    selectBossPlayer = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.ResolveModifiers(MS_SCOPE_BOSSATT)
        local prevFocus = module.selectedBossPlayer

        -- Mutual exclusion: selecting a boss-attendee filter clears the raid-attendee filter (and its multi-select).
        clearSelection(module, "selectedPlayer", MS_CTX_RAIDATT)

        local ordered = module.BossAttendees and module.BossAttendees._ctrl and module.BossAttendees._ctrl.data or nil
        local action, count = applyModuleFocusedMultiSelect(id, MS_CTX_BOSSATT, ordered, isMulti, isRange, "selectedBossPlayer")

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickBossAttendees):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedBossPlayer)
                )
            )
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedBossPlayer then
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
        end

        triggerSelectionEvent(module, "selectedBossPlayer")
        triggerSelectionEvent(module, "selectedPlayer")
    end

    selectPlayer = function(btn, button)
        if button and button ~= "LeftButton" then
            return
        end
        local id = btn and btn.GetID and btn:GetID()
        if not id then
            return
        end

        local isMulti, isRange = MultiSelect.ResolveModifiers(MS_SCOPE_RAIDATT)
        local prevFocus = module.selectedPlayer

        -- Mutual exclusion: selecting a raid-attendee filter clears the boss-attendee filter (and its multi-select).
        clearSelection(module, "selectedBossPlayer", MS_CTX_BOSSATT)

        local ordered = module.RaidAttendees and module.RaidAttendees._ctrl and module.RaidAttendees._ctrl.data or nil
        local action, count = applyModuleFocusedMultiSelect(id, MS_CTX_RAIDATT, ordered, isMulti, isRange, "selectedPlayer")

        if Options.IsDebugEnabled() and addon.debug then
            addon:debug(
                (Diag.D.LogLoggerSelectClickRaidAttendees):format(
                    tostring(id),
                    isMulti and 1 or 0,
                    isRange and 1 or 0,
                    tostring(action),
                    tonumber(count) or 0,
                    tostring(module.selectedPlayer)
                )
            )
        end

        -- If the focused attendee changed, reset loot (multi) selection (filter changed).
        if prevFocus ~= module.selectedPlayer then
            clearSelection(module, "selectedItem", MS_CTX_LOOT)
            triggerSelectionEvent(module, "selectedItem")
        end

        triggerSelectionEvent(module, "selectedPlayer")
        triggerSelectionEvent(module, "selectedBossPlayer")
    end

    -- Item: left select, right menu
    do
        local quickRollTypes = {
            { rollType = rollTypes.MAINSPEC, label = L.BtnMS, suffix = "MS" },
            { rollType = rollTypes.OFFSPEC, label = L.BtnOS, suffix = "OS" },
            { rollType = rollTypes.RESERVED, label = L.BtnSR, suffix = "SR" },
            { rollType = rollTypes.FREE, label = L.BtnFree, suffix = "Free" },
            { rollType = rollTypes.BANK, label = L.BtnBank, suffix = "Bank" },
            { rollType = rollTypes.DISENCHANT, label = L.BtnDisenchant, suffix = "DE" },
            { rollType = rollTypes.HOLD, label = L.BtnHold, suffix = "Hold" },
        }
        local ROLLTYPE_POPUP_KEY = "KRTLOGGER_ITEM_EDIT_ROLL_PICK"
        local ROLLTYPE_PICKER_FRAME = "KRTLoggerRollTypePickerFrame"
        local ROLLTYPE_BUTTON_MIN_WIDTH = 42
        local ROLLTYPE_BUTTON_MAX_WIDTH = 54
        local ROLLTYPE_BUTTON_HEIGHT = 22
        local ROLLTYPE_BUTTON_SPACING = 3
        local ROLLTYPE_PICKER_SIDE_PADDING = 24
        local ROLLTYPE_PICKER_TOP_OFFSET = 8
        local ROLLTYPE_POPUP_EXTRA_HEIGHT = 16

        local function applySelectedLootRollType(lootNid, rollType)
            if not lootNid then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end
            setLootEntry(lootNid, nil, rollType, nil, "LOGGER_EDIT_ROLLTYPE")
        end

        local function getItemMenuFrame()
            return _G.KRTLoggerItemMenuFrame or CreateFrame("Frame", "KRTLoggerItemMenuFrame", UIParent, "UIDropDownMenuTemplate")
        end

        local function ensureRollTypeInsertedFrame()
            local frame = _G[ROLLTYPE_PICKER_FRAME]
            if not frame then
                return nil
            end

            if frame._buttons and frame._initialized then
                return frame
            end

            frame._buttons = frame._buttons or {}
            local frameName = frame.GetName and frame:GetName() or ROLLTYPE_PICKER_FRAME
            local count = #quickRollTypes
            for i = 1, count do
                local entry = quickRollTypes[i]
                local rollType = entry.rollType
                local button = _G[frameName .. entry.suffix]
                if button then
                    button:SetText(entry.label)
                    button:SetScript("OnClick", function(btn)
                        local parent = btn and btn.GetParent and btn:GetParent() or nil
                        applySelectedLootRollType(parent and parent.lootNid, rollType)
                        StaticPopup_Hide(ROLLTYPE_POPUP_KEY)
                    end)
                end
                frame._buttons[i] = button
            end
            frame._initialized = true
            return frame
        end

        local function layoutRollTypeInsertedFrame(popup, picker)
            local count = #quickRollTypes
            local spacing = ROLLTYPE_BUTTON_SPACING
            local sidePadding = ROLLTYPE_PICKER_SIDE_PADDING
            local popupWidth = popup:GetWidth()

            local available = popupWidth - (sidePadding * 2) - (spacing * (count - 1))
            local buttonWidth = math.floor(available / count)
            if buttonWidth < ROLLTYPE_BUTTON_MIN_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MIN_WIDTH
                local minPopupWidth = (buttonWidth * count) + (spacing * (count - 1)) + (sidePadding * 2)
                if popupWidth < minPopupWidth then
                    popup:SetWidth(minPopupWidth)
                    popupWidth = popup:GetWidth()
                    available = popupWidth - (sidePadding * 2) - (spacing * (count - 1))
                    buttonWidth = math.floor(available / count)
                end
            end
            if buttonWidth > ROLLTYPE_BUTTON_MAX_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MAX_WIDTH
            end
            if buttonWidth < ROLLTYPE_BUTTON_MIN_WIDTH then
                buttonWidth = ROLLTYPE_BUTTON_MIN_WIDTH
            end

            local rowWidth = (buttonWidth * count) + (spacing * (count - 1))
            picker:SetWidth(rowWidth)
            picker:SetHeight(ROLLTYPE_BUTTON_HEIGHT)

            local prevButton
            for i = 1, count do
                local button = picker._buttons and picker._buttons[i]
                if button then
                    button:ClearAllPoints()
                    button:SetWidth(buttonWidth)
                    button:SetHeight(ROLLTYPE_BUTTON_HEIGHT)
                    if i == 1 then
                        button:SetPoint("LEFT", picker, "LEFT", 0, 0)
                    else
                        button:SetPoint("LEFT", prevButton, "RIGHT", spacing, 0)
                    end
                    prevButton = button
                end
            end
        end

        local function ensureRollTypePopup()
            if not StaticPopupDialogs then
                return false
            end
            if StaticPopupDialogs[ROLLTYPE_POPUP_KEY] then
                return true
            end

            ensureRollTypeInsertedFrame()

            StaticPopupDialogs[ROLLTYPE_POPUP_KEY] = {
                text = L.StrEditItemRollType,
                button1 = L.BtnCancel,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                wide = 1,
                preferredIndex = 3,
                OnShow = function(self, data)
                    local itemId = data and data.itemId or module.selectedItem
                    local picker = ensureRollTypeInsertedFrame()
                    if not picker then
                        return
                    end
                    self._krtExtraHeight = picker:GetHeight() + ROLLTYPE_POPUP_EXTRA_HEIGHT

                    if not self._krtSavedSetHeight then
                        self._krtSavedSetHeight = self.SetHeight
                        self.SetHeight = function(dialog, h)
                            local base = dialog._krtSavedSetHeight
                            if not base then
                                return
                            end
                            local extra = dialog._krtExtraHeight or 0
                            return base(dialog, h + extra)
                        end
                    end

                    if self.text then
                        self.text:SetWidth(self:GetWidth() - 36)
                    end
                    if StaticPopup_Resize then
                        StaticPopup_Resize(self, self.which)
                    end
                    layoutRollTypeInsertedFrame(self, picker)

                    picker.lootNid = itemId
                    picker:SetParent(self)
                    picker:ClearAllPoints()
                    if self.text then
                        picker:SetPoint("TOP", self.text, "BOTTOM", 0, -ROLLTYPE_PICKER_TOP_OFFSET)
                    else
                        picker:SetPoint("TOP", self, "TOP", 0, -44)
                    end
                    picker:SetFrameLevel((self:GetFrameLevel() or 1) + 1)
                    picker:Show()
                end,
                OnHide = function(self)
                    if self._krtSavedSetHeight then
                        self.SetHeight = self._krtSavedSetHeight
                        self._krtSavedSetHeight = nil
                    end
                    self._krtExtraHeight = nil
                    local picker = _G[ROLLTYPE_PICKER_FRAME]
                    if picker then
                        picker.lootNid = nil
                        picker:Hide()
                        picker:SetParent(UIParent)
                    end
                end,
            }
            return true
        end

        local function openItemRollTypePopup()
            local lootNid = module.selectedItem
            if not lootNid then
                addon:error(L.ErrLoggerInvalidItem)
                return
            end

            if not ensureRollTypePopup() then
                return
            end

            CloseDropDownMenus()
            StaticPopup_Show(ROLLTYPE_POPUP_KEY, nil, nil, {
                itemId = lootNid,
            })
        end

        local function openItemMenu()
            local f = getItemMenuFrame()

            EasyMenu({
                {
                    text = L.StrEditItemLooter,
                    notCheckable = 1,
                    func = function()
                        StaticPopup_Show("KRTLOGGER_ITEM_EDIT_WINNER")
                    end,
                },
                {
                    text = L.StrEditItemRollType,
                    notCheckable = 1,
                    func = openItemRollTypePopup,
                },
                {
                    text = L.StrEditItemRollValue,
                    notCheckable = 1,
                    func = function()
                        StaticPopup_Show("KRTLOGGER_ITEM_EDIT_VALUE")
                    end,
                },
            }, f, "cursor", 0, 0, "MENU")
        end

        selectItem = function(btn, button)
            local id = btn and btn.GetID and btn:GetID()
            if not id then
                return
            end

            -- NOTE: Multi-select is maintained in MultiSelect module (context = MS_CTX_LOOT).
            if button == "LeftButton" then
                local isMulti, isRange = MultiSelect.ResolveModifiers(MS_SCOPE_LOOT)

                local ordered = module.Loot and module.Loot._ctrl and module.Loot._ctrl.data or nil
                local action, count = applyModuleFocusedMultiSelect(id, MS_CTX_LOOT, ordered, isMulti, isRange, "selectedItem")

                if Options.IsDebugEnabled() and addon.debug then
                    addon:debug(
                        (Diag.D.LogLoggerSelectClickLoot):format(
                            tostring(id),
                            isMulti and 1 or 0,
                            isRange and 1 or 0,
                            tostring(action),
                            tonumber(count) or 0,
                            tostring(module.selectedItem)
                        )
                    )
                end

                triggerSelectionEvent(module, "selectedItem")
            elseif button == "RightButton" then
                -- Context menu works on a single focused row.
                local action, count = MultiSelect.Toggle(MS_CTX_LOOT, id, false)
                module.selectedItem = id

                if Options.IsDebugEnabled() and addon.debug then
                    addon:debug((Diag.D.LogLoggerSelectClickContextMenu):format(tostring(id), tostring(action), tonumber(count) or 0))
                end

                triggerSelectionEvent(module, "selectedItem")
                openItemMenu()
            end
        end

        -- Keep row hover neutral; item tooltip is bound to icon hover only.
        onLootRowEnter = function(_row)
            -- No-op.
        end

        onLootRowLeave = function(_row)
            -- No-op.
        end

        local function validateRollValue(_, text)
            local ok, value = isValidRollValue(text)
            if not ok then
                addon:error(L.ErrLoggerInvalidRollValue)
                return false
            end
            return true, value
        end

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_WINNER", L.StrEditItemLooterHelp, function(self, text)
            local winner, err = Actions:ResolveLootEditWinner(self.raidId, self.lootNid, text)
            if not winner then
                addon:error(err or L.ErrLoggerWinnerEmpty)
                return
            end

            setLootEntry(self.lootNid, winner, nil, nil, "LOGGER_EDIT_WINNER")
        end, function(self)
            self.raidId = module.selectedRaid
            self.lootNid = module.selectedItem
        end)

        Frames.MakeEditBoxPopup("KRTLOGGER_ITEM_EDIT_VALUE", L.StrEditItemRollValueHelp, function(self, text)
            setLootEntry(self.lootNid, nil, nil, text, "LOGGER_EDIT_ROLLVALUE")
        end, function(self)
            self.lootNid = module.selectedItem
        end, validateRollValue)
    end
end

-- Shared factory for Logger list controllers with standardized highlight/focus config.
local function makeLoggerList(cfg, selField, msCtxField, hlOpts)
    hlOpts = hlOpts or {}
    local transform = hlOpts.transform
    local debugTag = hlOpts.debugTag or "LoggerSelect"

    -- Logger XML already reserves a right scrollbar column via ScrollFrame anchors.
    -- Keep ListController from subtracting a second right inset in Logger tables.
    if cfg.rightInset == nil then
        cfg.rightInset = 0
    end
    if cfg.drawRow then
        local drawRow = cfg.drawRow
        local rowHeight = cfg.rowHeight or (cfg.poolTag == "logger-loot" and LOGGER_LOOT_ROW_HEIGHT or LOGGER_COMPACT_ROW_HEIGHT)
        cfg.drawRow = function(row, it, visibleIndex)
            setLoggerRowIndex(row, visibleIndex)
            if row.SetHeight then
                row:SetHeight(rowHeight)
            end
            drawRow(row, it, visibleIndex)
            return rowHeight
        end
    end

    local function resolve()
        local v = module[selField]
        if v == nil then
            return nil
        end
        return transform and transform(v) or v
    end

    if msCtxField then
        cfg.highlightFn = function(id)
            return MultiSelect.IsSelected(module[msCtxField], id)
        end
        cfg.highlightKey = function()
            return MultiSelect.GetVersion(module[msCtxField])
        end
        cfg.highlightDebugInfo = function()
            return ("ctx=%s selectedCount=%d"):format(tostring(module[msCtxField]), MultiSelect.GetCount(module[msCtxField]))
        end
    else
        cfg.highlightId = resolve
        cfg.highlightDebugInfo = function()
            return ("%s=%s"):format(selField, tostring(resolve()))
        end
    end

    cfg.focusId = resolve
    cfg.focusKey = function()
        return tostring(resolve() or "nil")
    end
    cfg.highlightDebugTag = debugTag
    return ListController.MakeListController(cfg)
end

-- Raids list.
do
    module.Raids = module.Raids or {}
    local Raids = module.Raids
    local Store = module.Store
    local controller
    local setCurrentRaidFromLogger
    local confirmDeleteSelectedRaids
    controller = makeLoggerList(
        {
            keyName = "RaidsList",
            poolTag = "logger-raids",
            _rowParts = { "ID", "Date", "Zone", "Size" },

            localize = function(n)
                local title = _G[n .. "Title"]
                if title then
                    title:SetText(L.StrRaidsList)
                end
                _G[n .. "HeaderNum"]:SetText(L.StrNumber)
                _G[n .. "HeaderDate"]:SetText(L.StrDate)
                _G[n .. "HeaderZone"]:SetText(L.StrZone)
                _G[n .. "HeaderSize"]:SetText(L.StrSize)
                applyRaidListColumnWidths(n)
                _G[n .. "CurrentBtn"]:SetText(L.StrSetCurrent)
                local del = _G[n .. "DeleteBtn"]
                if del then
                    del:SetText(L.BtnDelete)
                end
                Frames.SetTooltip(_G[n .. "CurrentBtn"], L.StrRaidsCurrentHelp, nil, L.StrRaidCurrentTitle)

                local frame = _G[n]
                if frame and not frame._krtBound then
                    Frames.SetScriptSafely(_G[n .. "CurrentBtn"], "OnClick", function(self, button)
                        setCurrentRaidFromLogger(self, button)
                    end)
                    Frames.SetScriptSafely(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                        confirmDeleteSelectedRaids(self, button)
                    end)
                    bindRaidSortHeaders(n, Raids)
                end
            end,

            getData = function(out)
                fillRaidListData(out, "Logger.Raids.GetData")
            end,

            rowName = function(n, _, i)
                return n .. "RaidBtn" .. i
            end,
            rowTmpl = "KRTLoggerRaidButton",

            drawRow = ListController.CreateRowDrawer(function(row, it)
                if not row._krtBound then
                    Frames.SetScriptSafely(row, "OnClick", function(self, button)
                        selectRaid(self, button)
                    end)
                    row._krtBound = true
                end
                local ui = row._p
                applyRaidRowColumnWidths(ui, "KRTLoggerRaids")
                ui.ID:SetText(it.seq or it.id)
                ui.Date:SetText(it.dateFmt)
                ui.Zone:SetText(it.zone)
                ui.Size:SetText(it.sizeLabel or it.size)
            end),

            postUpdate = function(n)
                applyRaidListColumnWidths(n)

                local sel = module.selectedRaid
                local raid = sel and Database.EnsureRaidById(sel) or nil
                local count = controller and controller.data and #controller.data or 0

                local canSetCurrent = false
                if sel and raid and sel ~= Database.GetCurrentRaid() then
                    -- This button is intended to resolve duplicate raid creation while actively raiding.
                    if not addon.IsInRaid() then
                        canSetCurrent = false
                    elseif Services.Raid:IsRaidExpired(sel) then
                        canSetCurrent = false
                    else
                        local instanceName, instanceType, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
                        if isDyn then
                            instanceDiff = instanceDiff + (2 * dynDiff)
                        end
                        if instanceType == "raid" then
                            local raidSize = tonumber(raid.size)
                            local groupSize = Services.Raid:GetRaidSize()
                            local zoneOk = (not raid.zone) or (raid.zone == instanceName)
                            local raidDiff = tonumber(raid.difficulty)
                            local curDiff = tonumber(instanceDiff)
                            local diffOk = raidDiff and curDiff and (raidDiff == curDiff)
                            canSetCurrent = zoneOk and raidSize and (raidSize == groupSize) and diffOk
                        end
                    end
                end

                UIPrimitives.EnableDisable(_G[n .. "CurrentBtn"], canSetCurrent)

                local ctx = module._msRaidCtx
                local selCount = MultiSelect.GetCount(ctx)
                local canDelete = (selCount and selCount > 0) or false
                if canDelete and Database.GetCurrentRaid() then
                    local currentRaidNid = Database.GetRaidNidById(Database.GetCurrentRaid())
                    local ids = MultiSelect.GetSelected(ctx)
                    for i = 1, #ids do
                        if currentRaidNid and tonumber(ids[i]) == tonumber(currentRaidNid) then
                            canDelete = false
                            break
                        end
                    end
                end
                local delBtn = _G[n .. "DeleteBtn"]
                UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, selCount)
                UIPrimitives.EnableDisable(delBtn, canDelete)
                setPanelTitle(n, getCountTitle(L.StrRaidsList, count))
                setFrameHint(n, "EmptyState", count == 0 and L.StrLoggerEmptyRaids or nil)
            end,

            sorters = {
                id = function(a, b, asc)
                    return CompareNumbers(a.seq or a.id, b.seq or b.id, asc, 0)
                end,
                date = function(a, b, asc)
                    return CompareNumbers(a.date, b.date, asc, 0)
                end,
                zone = function(a, b, asc)
                    return compareStrings(a.zone, b.zone, asc)
                end,
                size = function(a, b, asc)
                    return CompareNumbers(a.size, b.size, asc, 0)
                end,
            },
        },
        "selectedRaid",
        "_msRaidCtx",
        {
            transform = function(id)
                return Database.GetRaidNidById(id)
            end,
        }
    )

    Raids._ctrl = controller
    ListController.BindListController(Raids, controller)

    function setCurrentRaidFromLogger(btn)
        if not btn then
            return
        end
        local sel = module.selectedRaid
        if not sel then
            return
        end
        if module.Actions:SetCurrentRaid(sel) then
            -- Context change: clear dependent selections and redraw all module panels.
            SetSelectedRaid(sel)
            resetSelections()
            triggerSelectionEvent(module, "selectedRaid", "ui")
        end
    end

    do
        local function deleteRaids()
            local ctx = module._msRaidCtx
            local ids = MultiSelect.GetSelected(ctx)
            if not (ids and #ids > 0) then
                return
            end

            local raidNids = {}
            local seenNids = {}
            for i = 1, #ids do
                local nid = tonumber(ids[i])
                if nid and not seenNids[nid] then
                    seenNids[nid] = true
                    raidNids[#raidNids + 1] = nid
                end
            end
            if #raidNids == 0 then
                return
            end

            -- Safety: never delete the current raid
            local currentRaidNid = Database.GetRaidNidById(Database.GetCurrentRaid())
            if currentRaidNid then
                for i = 1, #raidNids do
                    if tonumber(raidNids[i]) == tonumber(currentRaidNid) then
                        return
                    end
                end
            end

            local prevFocus = module.selectedRaid
            local prevFocusNid = prevFocus and Database.GetRaidNidById(prevFocus) or nil
            for i = 1, #raidNids do
                module.Actions:DeleteRaidByNid(raidNids[i])
            end

            MultiSelect.EnsureState(ctx)

            local raidStore = Database.GetRaidStoreOrNil("Logger.Raids.DeleteRaids", { "GetAllRaids" })
            local raids = raidStore and raidStore:GetAllRaids() or {}
            local n = #raids
            local newFocus = nil
            if n > 0 then
                newFocus = prevFocusNid and Database.GetRaidIdByNid(prevFocusNid) or nil
                if not newFocus then
                    local base = tonumber(prevFocus) or n
                    if base > n then
                        base = n
                    end
                    if base < 1 then
                        base = 1
                    end
                    newFocus = base
                end
            end

            SetSelectedRaid(newFocus)
            resetSelections()
            controller:Dirty()
            triggerSelectionEvent(module, "selectedRaid", "ui")
        end

        function confirmDeleteSelectedRaids(btn)
            local ctx = module._msRaidCtx
            if btn and MultiSelect.GetCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAID")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAID", L.StrConfirmDeleteRaid, deleteRaids)
    end

    Bus.RegisterCallback(InternalEvents.RaidCreate, function(_, num)
        -- Context change: selecting a different raid must clear dependent selections.
        SetSelectedRaid(tonumber(num))
        resetSelections()
        controller:Dirty()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end)

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function(_, raidId, reason)
        local raidIdType = type(raidId)
        if raidId ~= nil and raidIdType ~= "number" and raidIdType ~= "string" then
            addon:warn(Diag.W.LogLoggerSelectRaidPayloadInvalid:format(tostring(raidId), tostring(reason)))
            return
        end
        if reason ~= nil and reason ~= "ui" and reason ~= "sync" then
            addon:warn(Diag.W.LogLoggerSelectRaidPayloadInvalid:format(tostring(raidId), tostring(reason)))
            return
        end

        local prevRaid = module.selectedRaid
        SetSelectedRaid(raidId)

        if prevRaid ~= module.selectedRaid then
            resetSelections()
        end

        if reason == "sync" then
            local raid = module.selectedRaid and Store:GetRaid(module.selectedRaid) or nil
            if raid and Store._InvalidateIndexes then
                Store._InvalidateIndexes(raid)
            end
        end

        if reason == "sync" then
            -- Sync can change raid rows; force data refetch instead of highlight-only refresh.
            controller:Dirty()
        else
            controller:Touch()
        end
    end)

    Bus.RegisterCallback(InternalEvents.RaidRosterDelta, function(_, delta, rosterVersion, raidId)
        local raidIdType = type(raidId)
        if type(delta) ~= "table" then
            return
        end
        if type(rosterVersion) ~= "number" then
            return
        end
        if raidId == nil then
            return
        end
        if raidIdType ~= "number" and raidIdType ~= "string" then
            return
        end
        if not isLoggerViewingCurrentRaid() then
            return
        end

        requestRosterBoundListsRefresh()
    end)
end

-- Boss list.
do
    module.Boss = module.Boss or {}
    local Boss = module.Boss
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions
    local showBossBoxFromLogger
    local editSelectedBoss
    local confirmDeleteSelectedBosses

    local controller
    controller = makeLoggerList({
        keyName = "BossList",
        poolTag = "logger-bosses",
        _rowParts = { "ID", "Name", "Time", "Mode" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrBosses)
            end
            _G[n .. "HeaderNum"]:SetText(L.StrNumber)
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
            _G[n .. "HeaderMode"]:SetText(L.StrMode)
            applyBossListColumnWidths(n)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            local del = _G[n .. "DeleteBtn"]
            if del then
                del:SetText(L.BtnDelete)
            end
            _G[n .. "DeleteBtn"]:SetText(L.BtnDelete)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SetScriptSafely(_G[n .. "AddBtn"], "OnClick", function()
                    showBossBoxFromLogger()
                end)
                Frames.SetScriptSafely(_G[n .. "EditBtn"], "OnClick", function()
                    editSelectedBoss()
                end)
                Frames.SetScriptSafely(_G[n .. "DeleteBtn"], "OnClick", function(self, button)
                    confirmDeleteSelectedBosses(self, button)
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderNum"], "OnClick", function()
                    Boss:Sort("id")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderName"], "OnClick", function()
                    Boss:Sort("name")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderTime"], "OnClick", function()
                    Boss:Sort("time")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderMode"], "OnClick", function()
                    Boss:Sort("mode")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end
            if module.activeTab == "attendance" then
                View:GetPlayerBossParticipationList(out, raid, module.selectedPlayer)
                return
            end
            View:FillBossList(out, raid)
        end,

        rowName = function(n, _, i)
            return n .. "BossBtn" .. i
        end,
        rowTmpl = "KRTLoggerBossButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SetScriptSafely(row, "OnClick", function(self, button)
                    if module.activeTab ~= "attendance" then
                        selectBoss(self, button)
                    end
                end)
                row._krtBound = true
            end
            local ui = row._p
            applyBossRowColumnWidths(ui, "KRTLoggerBosses")
            -- Display a sequential number that rescales after deletions.
            -- Keep it.id as the stable bossNid for selection/highlight.
            ui.ID:SetText(it.seq)
            ui.Name:SetText(it.name)
            ui.Time:SetText(it.timeFmt)
            ui.Mode:SetText(it.mode)
        end),

        postUpdate = function(n)
            applyBossListColumnWidths(n)

            local hasRaid = module.selectedRaid
            local hasBoss = module.selectedBoss
            local count = controller and controller.data and #controller.data or 0
            local isAttendanceTab = module.activeTab == "attendance"
            UIPrimitives.ShowHide(_G[n .. "AddBtn"], not isAttendanceTab)
            UIPrimitives.ShowHide(_G[n .. "EditBtn"], not isAttendanceTab)
            UIPrimitives.ShowHide(_G[n .. "DeleteBtn"], not isAttendanceTab)
            UIPrimitives.EnableDisable(_G[n .. "AddBtn"], hasRaid ~= nil)
            UIPrimitives.EnableDisable(_G[n .. "EditBtn"], hasBoss ~= nil)
            local bossSelCount = MultiSelect.GetCount(module._msBossCtx)
            local delBtn = _G[n .. "DeleteBtn"]
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, bossSelCount)
            UIPrimitives.EnableDisable(delBtn, (bossSelCount and bossSelCount > 0) or false)
            if isAttendanceTab then
                local playerLabel = getPlayerContextLabel(module.selectedRaid, module.selectedPlayer)
                setPanelTitle(n, getCountContextTitle(L.StrBossParticipation, count, playerLabel, nil))
                if not module.selectedRaid then
                    setFrameHint(n, "EmptyState", L.StrLoggerEmptyBossParticipationSelectRaid)
                elseif not module.selectedPlayer then
                    setFrameHint(n, "EmptyState", L.StrLoggerEmptyBossParticipationSelectPlayer)
                else
                    setFrameHint(n, "EmptyState", count == 0 and L.StrLoggerEmptyBossParticipation or "")
                end
            else
                setPanelTitle(n, getCountContextTitle(L.StrBosses, count, getRaidContextLabel(module.selectedRaid), nil))
                setFrameHint(n, "EmptyState", getBossEmptyStateText(count, module.selectedRaid))
            end
        end,

        sorters = {
            -- Sort by the displayed sequential number, not the stable nid.
            id = function(a, b, asc)
                return CompareNumbers(a.seq, b.seq, asc, 0)
            end,
            name = function(a, b, asc)
                return compareStrings(a.name, b.name, asc)
            end,
            time = function(a, b, asc)
                return CompareNumbers(a.time, b.time, asc, 0)
            end,
            mode = function(a, b, asc)
                return compareStrings(a.mode, b.mode, asc)
            end,
        },
    }, "selectedBoss", "_msBossCtx")

    Boss._ctrl = controller
    ListController.BindListController(Boss, controller)

    showBossBoxFromLogger = function()
        module.BossBox:Toggle()
    end

    editSelectedBoss = function()
        if module.selectedBoss then
            fillBossBox()
        end
    end

    do
        local function deleteBosses()
            runWithSelectedRaid(function(_, rID)
                local ctx = module._msBossCtx
                local ids = MultiSelect.GetSelected(ctx)
                if not (ids and #ids > 0) then
                    return
                end

                for i = 1, #ids do
                    local bNid = ids[i]
                    local lootRemoved = Actions:DeleteBoss(rID, bNid)
                    if addon.hasDebug then
                        addon:debug(Diag.D.LogLoggerBossLootRemoved, rID, tonumber(bNid) or -1, lootRemoved)
                    end
                end

                -- Clear boss-related selections (filters changed / deleted)
                MultiSelect.EnsureState(ctx)
                module.selectedBoss = nil

                module.selectedBossPlayer = nil
                MultiSelect.EnsureState(module._msBossAttCtx)

                module.selectedItem = nil
                MultiSelect.EnsureState(module._msLootCtx)
            end)
        end

        confirmDeleteSelectedBosses = function()
            local ctx = module._msBossCtx
            if MultiSelect.GetCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_BOSS")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_BOSS", L.StrConfirmDeleteBoss, deleteBosses)
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function()
        controller:Dirty()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectBoss, function()
        controller:Touch()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectPlayer, function()
        if module.activeTab == "attendance" then
            controller:Dirty()
        end
    end)
end

-- Boss attendees list.
do
    module.BossAttendees = module.BossAttendees or {}
    local BossAtt = module.BossAttendees
    local Store = module.Store
    local View = module.View
    local Actions = module.Actions
    local showBossAttendeesBoxFromLogger
    local confirmDeleteSelectedBossAttendees

    local controller
    controller = makeLoggerList({
        keyName = "BossAttendeesList",
        poolTag = "logger-boss-attendees",
        _rowParts = { "Name" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrBossAttendees)
            end
            local add = _G[n .. "AddBtn"]
            if add then
                add:SetText(L.BtnAdd)
            end
            local rm = _G[n .. "RemoveBtn"]
            if rm then
                rm:SetText(L.BtnRemove)
            end
            _G[n .. "HeaderName"]:SetText(L.StrName)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SetScriptSafely(_G[n .. "AddBtn"], "OnClick", function()
                    showBossAttendeesBoxFromLogger()
                end)
                Frames.SetScriptSafely(_G[n .. "RemoveBtn"], "OnClick", function(self, button)
                    confirmDeleteSelectedBossAttendees(self, button)
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderName"], "OnClick", function()
                    BossAtt:Sort("name")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local rID = module.selectedRaid
            local bID = module.selectedBoss
            local raid = (rID and bID) and Store:GetRaid(rID) or nil
            if not (raid and bID) then
                return
            end
            View:FillBossAttendeesList(out, raid, bID)
        end,

        rowName = function(n, _, i)
            return n .. "PlayerBtn" .. i
        end,
        rowTmpl = "KRTLoggerBossAttendeeButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SetScriptSafely(row, "OnClick", function(self, button)
                    selectBossPlayer(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            local r, g, b = Colors.GetClassColor(it.class)
            ui.Name:SetText(it.name)
            ui.Name:SetVertexColor(r, g, b)
        end),

        postUpdate = function(n)
            local bSel = module.selectedBoss
            local addBtn = _G[n .. "AddBtn"]
            local removeBtn = _G[n .. "RemoveBtn"]
            local attSelCount = MultiSelect.GetCount(module._msBossAttCtx)
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, getCountContextTitle(L.StrBossAttendees, count, getBossContextLabel(module.selectedRaid, module.selectedBoss), nil))
            setFrameHint(n, "EmptyState", getBossAttendeesEmptyStateText(count, module.selectedRaid, module.selectedBoss))
            if addBtn then
                UIPrimitives.EnableDisable(addBtn, bSel and ((attSelCount or 0) == 0))
            end
            if removeBtn then
                UIPrimitives.SetButtonCount(removeBtn, L.BtnRemove, attSelCount)
                UIPrimitives.EnableDisable(removeBtn, bSel and ((attSelCount or 0) > 0))
            end
        end,

        sorters = {
            name = function(a, b, asc)
                return compareStrings(a.name, b.name, asc)
            end,
        },
    }, "selectedBossPlayer", "_msBossAttCtx")

    BossAtt._ctrl = controller
    ListController.BindListController(BossAtt, controller)

    function showBossAttendeesBoxFromLogger()
        module.AttendeesBox:Toggle()
    end

    do
        local function deleteSelectedBossAttendees()
            deleteSelectedAttendees(module._msBossAttCtx, function(rID, ids)
                local bNid = module.selectedBoss
                if not bNid then
                    return 0
                end

                for i = 1, #ids do
                    Actions:DeleteBossAttendee(rID, bNid, ids[i])
                end
                return #ids
            end, function()
                module.selectedBossPlayer = nil
            end)
        end

        function confirmDeleteSelectedBossAttendees()
            local ctx = module._msBossAttCtx
            if MultiSelect.GetCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ATTENDEE", L.StrConfirmDeleteAttendee, deleteSelectedBossAttendees)
    end

    local refreshEvents = {
        InternalEvents.LoggerSelectRaid,
        InternalEvents.LoggerSelectBoss,
    }
    for i = 1, #refreshEvents do
        Bus.RegisterCallback(refreshEvents[i], function()
            controller:Dirty()
        end)
    end
    Bus.RegisterCallback(InternalEvents.LoggerSelectBossPlayer, function()
        controller:Touch()
    end)
end

-- Raid attendees list.
do
    module.RaidAttendees = module.RaidAttendees or {}
    local RaidAtt = module.RaidAttendees
    local View = module.View
    local Actions = module.Actions
    local updateRaidAttendeesFromRoster
    local confirmDeleteSelectedRaidAttendees

    local controller
    controller = makeLoggerList({
        keyName = "RaidAttendeesList",
        poolTag = "logger-raid-attendees",
        _rowParts = { "Name", "Join", "Leave" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrRaidAttendees)
            end
            _G[n .. "HeaderName"]:SetText(L.StrName)
            _G[n .. "HeaderJoin"]:SetText(L.StrJoin)
            _G[n .. "HeaderLeave"]:SetText(L.StrLeave)
            applyAttendanceListColumnWidths(n)
            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                addBtn:SetText(L.BtnUpdate)
                local del = _G[n .. "DeleteBtn"]
                if del then
                    del:SetText(L.BtnDelete)
                end
                addBtn:Disable() -- enabled in postUpdate when applicable
            end

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SetScriptSafely(_G[n .. "AddBtn"], "OnClick", function()
                    updateRaidAttendeesFromRoster()
                end)
                Frames.SetScriptSafely(_G[n .. "DeleteBtn"], "OnClick", function()
                    confirmDeleteSelectedRaidAttendees()
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderName"], "OnClick", function()
                    RaidAtt:Sort("name")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderJoin"], "OnClick", function()
                    RaidAtt:Sort("join")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderLeave"], "OnClick", function()
                    RaidAtt:Sort("leave")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end
            View:FillRaidAttendeesList(out, raid)
        end,

        rowName = function(n, _, i)
            return n .. "PlayerBtn" .. i
        end,
        rowTmpl = "KRTLoggerRaidAttendeeButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            if not row._krtBound then
                Frames.SetScriptSafely(row, "OnClick", function(self, button)
                    selectPlayer(self, button)
                end)
                row._krtBound = true
            end
            local ui = row._p
            applyAttendanceRowColumnWidths(ui, "KRTLoggerRaidAttendees")
            ui.Name:SetText(it.name)
            local r, g, b = Colors.GetClassColor(it.class)
            ui.Name:SetVertexColor(r, g, b)
            ui.Join:SetText(it.joinFmt)
            ui.Leave:SetText(it.leaveFmt)
        end),

        postUpdate = function(n)
            applyAttendanceListColumnWidths(n)

            local deleteBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            setPanelTitle(n, getCountContextTitle(L.StrRaidAttendees, count, getRaidContextLabel(module.selectedRaid), nil))
            setFrameHint(n, "EmptyState", getRaidAttendeesEmptyStateText(count, module.selectedRaid))
            if deleteBtn then
                local attSelCount = MultiSelect.GetCount(module._msRaidAttCtx)
                UIPrimitives.SetButtonCount(deleteBtn, L.BtnDelete, attSelCount)
                UIPrimitives.EnableDisable(deleteBtn, (attSelCount and attSelCount > 0) or false)
            end

            local addBtn = _G[n .. "AddBtn"]
            if addBtn then
                -- Update is only meaningful for the current raid session while actively raiding.
                local can = addon.IsInRaid() and Database.GetCurrentRaid() and module.selectedRaid and (tonumber(Database.GetCurrentRaid()) == tonumber(module.selectedRaid))
                UIPrimitives.EnableDisable(addBtn, can)
            end
        end,

        sorters = {
            name = function(a, b, asc)
                return compareStrings(a.name, b.name, asc)
            end,
            join = function(a, b, asc)
                return CompareNumbers(a.join, b.join, asc, 0)
            end,
            leave = function(a, b, asc)
                local missing = asc and math.huge or -math.huge
                return CompareNumbers(a.leave, b.leave, asc, missing)
            end,
        },
    }, "selectedPlayer", "_msRaidAttCtx")

    RaidAtt._ctrl = controller
    ListController.BindListController(RaidAtt, controller)

    -- Update raid roster from the live in-game raid roster (current raid only).
    -- Bound to the "Add" button in the RaidAttendees frame (repurposed as Update).
    function updateRaidAttendeesFromRoster()
        runWithSelectedRaid(function(_, rID)
            local sel = tonumber(rID)
            if not sel then
                return
            end

            if not addon.IsInRaid() then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotInRaid)
                return
            end

            if not (Database.GetCurrentRaid() and tonumber(Database.GetCurrentRaid()) == sel) then
                addon:warn(Diag.W.ErrLoggerUpdateRosterNotCurrent)
                return
            end

            -- Update the roster from the live in-game raid roster.
            Services.Raid:UpdateRaidRoster()

            -- Clear dependent selections after roster sync.
            MultiSelect.EnsureState(module._msRaidAttCtx)
            MultiSelect.EnsureState(module._msBossAttCtx)
            MultiSelect.EnsureState(module._msLootCtx)
            module.selectedPlayer = nil
            module.selectedBossPlayer = nil
            module.selectedItem = nil

            controller:Dirty()
        end)
    end

    do
        local function deleteSelectedRaidAttendees()
            deleteSelectedAttendees(module._msRaidAttCtx, function(rID, ids)
                local removed = Actions:DeleteRaidAttendeeMany(rID, ids)
                return tonumber(removed) or 0
            end, function()
                module.selectedPlayer = nil

                -- Player filters changed: clear boss-attendees selection too.
                module.selectedBossPlayer = nil
                MultiSelect.EnsureState(module._msBossAttCtx)

                -- Filters changed: reset loot selection.
                module.selectedItem = nil
                MultiSelect.EnsureState(module._msLootCtx)
            end)
        end

        function confirmDeleteSelectedRaidAttendees()
            local ctx = module._msRaidAttCtx
            if MultiSelect.GetCount(ctx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_RAIDATTENDEE")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_RAIDATTENDEE", L.StrConfirmDeleteAttendee, deleteSelectedRaidAttendees)
    end

    Bus.RegisterCallback(InternalEvents.LoggerSelectRaid, function()
        controller:Dirty()
    end)
    Bus.RegisterCallback(InternalEvents.LoggerSelectPlayer, function()
        controller:Touch()
    end)
end

-- Loot list.
do
    module.Loot = module.Loot or {}
    local Loot = module.Loot
    local View = module.View
    local Actions = module.Actions
    local sortLoot
    local showLootTooltip
    local confirmDeleteSelectedLootItems

    local function updateSourceHeaderState(frameName)
        local header = frameName and _G[frameName .. "HeaderSource"]
        if not header then
            return
        end

        local canSortSource = module.selectedBoss == nil
        if header.EnableMouse then
            header:EnableMouse(canSortSource)
        end
        if header.SetAlpha then
            header:SetAlpha(canSortSource and 1 or 0.6)
        end
    end

    local controller
    controller = makeLoggerList({
        keyName = "LootList",
        poolTag = "logger-loot",
        _rowParts = { "Name", "Source", "Winner", "Type", "Roll", "Time", "ItemIconTexture", "ItemNormalTexture" },

        localize = function(n)
            local title = _G[n .. "Title"]
            if title then
                title:SetText(L.StrRaidLoot)
            end
            _G[n .. "ExportBtn"]:SetText(L.BtnExport)
            _G[n .. "ClearBtn"]:SetText(L.BtnClear)
            _G[n .. "AddBtn"]:SetText(L.BtnAdd)
            _G[n .. "EditBtn"]:SetText(L.BtnEdit)
            _G[n .. "HeaderItem"]:SetText(L.StrItem)
            _G[n .. "HeaderSource"]:SetText(L.StrSource)
            _G[n .. "HeaderWinner"]:SetText(L.StrWinner)
            _G[n .. "HeaderType"]:SetText(L.StrType)
            _G[n .. "HeaderRoll"]:SetText(L.StrRoll)
            _G[n .. "HeaderTime"]:SetText(L.StrTime)
            applyLootListColumnWidths(n)

            _G[n .. "ClearBtn"]:Disable()
            _G[n .. "AddBtn"]:Disable()
            local del = _G[n .. "DeleteBtn"]
            if del then
                del:SetText(L.BtnDelete)
            end
            _G[n .. "EditBtn"]:Disable()
            UIPrimitives.EnableDisable(_G[n .. "ExportBtn"], module.selectedRaid ~= nil)
            updateSourceHeaderState(n)

            local frame = _G[n]
            if frame and not frame._krtBound then
                Frames.SetScriptSafely(_G[n .. "ExportBtn"], "OnClick", function()
                    showLoggerExportFrame()
                end)
                Frames.SetScriptSafely(_G[n .. "DeleteBtn"], "OnClick", function()
                    confirmDeleteSelectedLootItems()
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderItem"], "OnClick", function()
                    sortLoot("id")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderSource"], "OnClick", function()
                    sortLoot("source")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderWinner"], "OnClick", function()
                    sortLoot("winner")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderType"], "OnClick", function()
                    sortLoot("type")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderRoll"], "OnClick", function()
                    sortLoot("roll")
                end)
                Frames.SetScriptSafely(_G[n .. "HeaderTime"], "OnClick", function()
                    sortLoot("time")
                end)
                frame._krtBound = true
            end
        end,

        getData = function(out)
            local raid = needRaid()
            if not raid then
                return
            end

            View:FillLootList(out, raid, nil, nil)
        end,

        rowName = function(n, _, i)
            return n .. "ItemBtn" .. i
        end,
        rowTmpl = "KRTLoggerLootButton",

        drawRow = ListController.CreateRowDrawer(function(row, it)
            local ui = row._p
            applyLootRowColumnWidths(ui, "KRTLoggerLoot")
            if not row._krtBound then
                if row.RegisterForClicks then
                    row:RegisterForClicks("AnyUp")
                end
                Frames.SetScriptSafely(row, "OnClick", function(self, button)
                    selectItem(self, button)
                end)
                Frames.SetScriptSafely(row, "OnEnter", function(self)
                    onLootRowEnter(self)
                end)
                Frames.SetScriptSafely(row, "OnLeave", function(self)
                    onLootRowLeave(self)
                end)
                local itemButton = row.GetName and _G[row:GetName() .. "Item"] or nil
                if itemButton and itemButton.EnableMouse then
                    itemButton:EnableMouse(true)
                end
                if itemButton and itemButton.RegisterForClicks then
                    itemButton:RegisterForClicks("AnyUp")
                end
                if itemButton then
                    itemButton._krtRow = row
                    Frames.SetScriptSafely(itemButton, "OnClick", function(_, button)
                        selectItem(row, button)
                    end)
                    Frames.SetScriptSafely(itemButton, "OnEnter", function(self)
                        showLootTooltip(self)
                    end)
                    Frames.SetScriptSafely(itemButton, "OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                -- Size the slot background to the button and the icon inset to reveal it.
                if ui.ItemNormalTexture and ui.ItemNormalTexture.SetSize then
                    ui.ItemNormalTexture:SetSize(26, 26)
                end
                if ui.ItemIconTexture and ui.ItemIconTexture.SetSize then
                    ui.ItemIconTexture:SetSize(20, 20)
                end
                row._krtBound = true
            end

            local itemButton = row.GetName and _G[row:GetName() .. "Item"] or nil
            if itemButton then
                itemButton._krtRow = row
                if itemButton.EnableMouse then
                    itemButton:EnableMouse(true)
                end
            end

            -- Preserve a tooltip-ready hyperlink on the pooled row.
            row._itemLink = it.itemLink
            local itemId = tonumber(it.itemId)
            row._itemTooltipLink = it.itemLink or (itemId and itemId > 0 and ("item:" .. itemId) or nil)
            local nameText = it.itemLink or it.itemName or ("[Item " .. (it.itemId or "?") .. "]")
            if it.itemLink then
                ui.Name:SetText(nameText)
            else
                ui.Name:SetText(addon.WrapTextInColorCode(nameText, Colors.NormalizeHexColor(itemColors[(it.itemRarity or 1) + 1])))
            end

            local selectedBoss = module.selectedBoss
            if selectedBoss and tonumber(it.bossNid) == tonumber(selectedBoss) then
                ui.Source:SetText("")
            else
                ui.Source:SetText(it.sourceName or "")
            end
            ui.Source:SetVertexColor(0.86, 0.82, 0.72)

            local winnerClass = it.looterClass or Services.Raid:GetPlayerClass(it.looter)
            local r, g, b = Colors.GetClassColor(winnerClass)
            ui.Winner:SetText(it.looter or "")
            ui.Winner:SetVertexColor(r, g, b)

            local rt = tonumber(it.rollType)
            it.rollType = rt
            ui.Type:SetText((rt and lootTypesColored[rt]) or "")
            ui.Roll:SetText(it.rollValue or 0)
            ui.Roll:SetVertexColor(0.95, 0.95, 0.95)
            ui.Time:SetText(it.timeFmt)
            ui.Time:SetVertexColor(0.86, 0.82, 0.72)

            local icon = it.itemTexture
            if not icon and it.itemId then
                icon = GetItemIcon(it.itemId)
            end
            if not icon then
                icon = C.RESERVES_ITEM_FALLBACK_ICON
            end
            ui.ItemIconTexture:SetTexture(icon)
            ui.ItemIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end),

        postUpdate = function(n)
            applyLootListColumnWidths(n)
            updateSourceHeaderState(n)

            local lootSelCount = MultiSelect.GetCount(module._msLootCtx)
            local exportBtn = _G[n .. "ExportBtn"]
            local delBtn = _G[n .. "DeleteBtn"]
            local count = controller and controller.data and #controller.data or 0
            UIPrimitives.EnableDisable(exportBtn, module.selectedRaid ~= nil)
            UIPrimitives.SetButtonCount(delBtn, L.BtnDelete, lootSelCount)
            UIPrimitives.EnableDisable(delBtn, (lootSelCount or 0) > 0)
            setPanelTitle(n, getCountContextTitle(L.StrRaidLoot, count, getLootPanelContextLabel(module), nil))
            setFrameHint(n, "EmptyState", getLootEmptyStateText(count, module))
        end,

        sorters = {
            id = function(a, b, asc)
                return compareLootTie(a, b, asc)
            end,
            source = function(a, b, asc)
                local aSource = strlower(tostring((a and a.sourceName) or ""))
                local bSource = strlower(tostring((b and b.sourceName) or ""))
                if aSource ~= bSource then
                    return CompareValues(aSource, bSource, asc)
                end
                return compareLootTie(a, b, asc)
            end,
            winner = function(a, b, asc)
                local aWinner = strlower(tostring((a and a.looter) or ""))
                local bWinner = strlower(tostring((b and b.looter) or ""))
                if aWinner ~= bWinner then
                    return CompareValues(aWinner, bWinner, asc)
                end
                return compareLootTie(a, b, asc)
            end,
            type = function(a, b, asc)
                local aType = tonumber(a and a.rollType) or 0
                local bType = tonumber(b and b.rollType) or 0
                if aType ~= bType then
                    return CompareValues(aType, bType, asc)
                end
                return compareLootTie(a, b, asc)
            end,
            roll = function(a, b, asc)
                local aRoll = tonumber(a and a.rollValue) or 0
                local bRoll = tonumber(b and b.rollValue) or 0
                if aRoll ~= bRoll then
                    return CompareValues(aRoll, bRoll, asc)
                end
                return compareLootTie(a, b, asc)
            end,
            time = function(a, b, asc)
                local aTime = tonumber(a and a.time) or 0
                local bTime = tonumber(b and b.time) or 0
                if aTime ~= bTime then
                    return CompareValues(aTime, bTime, asc)
                end
                return compareLootTie(a, b, asc)
            end,
        },
    }, "selectedItem", "_msLootCtx")

    Loot._ctrl = controller
    ListController.BindListController(Loot, controller)

    sortLoot = function(key)
        if key == "source" and module.selectedBoss then
            return
        end
        controller:Sort(key)
    end

    showLootTooltip = function(widget)
        if not widget then
            return
        end

        local row = widget._krtRow
        if not row then
            row = widget
            -- Climb parents until we find the pooled row carrying tooltip data.
            while row and not (row._itemTooltipLink or row._itemLink) do
                row = row.GetParent and row:GetParent() or nil
            end
        end
        if not row then
            return
        end

        local link = row._itemTooltipLink or row._itemLink
        if not link then
            return
        end

        GameTooltip:SetOwner(widget, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
    end

    do
        local function deleteItem()
            runWithSelectedRaid(function(_, rID)
                local ctx = module._msLootCtx
                local selected = MultiSelect.GetSelected(ctx)
                if not selected or #selected == 0 then
                    return
                end

                local removed = Actions:DeleteLootMany(rID, selected)
                if removed > 0 then
                    MultiSelect.EnsureState(ctx)
                    module.selectedItem = nil
                    triggerSelectionEvent(module, "selectedItem")

                    if Options.IsDebugEnabled() and addon.debug then
                        addon:debug((Diag.D.LogLoggerSelectDeleteItems):format(removed))
                    end
                end
            end)
        end

        confirmDeleteSelectedLootItems = function()
            if MultiSelect.GetCount(module._msLootCtx) > 0 then
                StaticPopup_Show("KRTLOGGER_DELETE_ITEM")
            end
        end

        controller._makeConfirmPopup("KRTLOGGER_DELETE_ITEM", L.StrConfirmDeleteItem, deleteItem)
    end

    local function resolveLoggerLootRaidId(source, raidIDOverride)
        if raidIDOverride then
            return raidIDOverride
        end

        -- If the module window is open and browsing an old raid, selectedRaid may
        -- differ from Database.GetCurrentRaid(). Runtime sources must always write
        -- into the current raid session; Logger UI edits target selectedRaid.
        local isLoggerSource = (type(source) == "string") and (source:find("^LOGGER_") ~= nil)
        if isLoggerSource then
            return module.selectedRaid or Database.GetCurrentRaid()
        end
        return Database.GetCurrentRaid() or module.selectedRaid
    end

    setLootEntry = function(lootNid, looter, rollType, rollValue, source, raidIDOverride)
        local raidID = resolveLoggerLootRaidId(source, raidIDOverride)
        local ok = Actions:SetLootEntry(raidID, lootNid, looter, rollType, rollValue, source)
        if ok then
            controller:Dirty()
        end
        return ok
    end

    Bus.RegisterCallback(InternalEvents.LoggerLootLogRequest, function(_, request)
        if type(request) ~= "table" then
            addon:error(Diag.E.LogLoggerLootLogRequestPayloadInvalid:format(type(request)))
            return
        end
        local raidId = request.raidId or request.raidID
        local lootNid = request.lootNid or request.itemID
        request.ok = setLootEntry(lootNid, request.looter, request.rollType, request.rollValue, request.source, raidId) == true
    end)

    local lootUiRefreshDebounceSeconds = 0.10

    local function reset()
        controller:Dirty()
    end

    local function requestLootRefresh(_, raidId)
        local selectedRaid = tonumber(module.selectedRaid)
        local eventRaid = tonumber(raidId)
        if eventRaid and selectedRaid and eventRaid ~= selectedRaid then
            return
        end

        if module._lootUiHandle then
            module:CancelTimer(module._lootUiHandle)
            module._lootUiHandle = nil
        end
        module._lootUiHandle = module:ScheduleTimer(function()
            module._lootUiHandle = nil
            controller:Dirty()
        end, lootUiRefreshDebounceSeconds)
    end

    local resetEvents = {
        InternalEvents.LoggerSelectRaid,
        InternalEvents.LoggerSelectBoss,
        InternalEvents.LoggerSelectPlayer,
        InternalEvents.LoggerSelectBossPlayer,
    }
    for i = 1, #resetEvents do
        Bus.RegisterCallback(resetEvents[i], reset)
    end
    Bus.RegisterCallback(InternalEvents.RaidLootUpdate, requestLootRefresh)
    Bus.RegisterCallback(InternalEvents.LoggerSelectItem, function()
        controller:Touch()
    end)
end

local function ensurePopupRefs(box)
    if not box then
        return nil
    end
    if box.refs then
        return box.refs
    end
    if type(box.BindUI) == "function" then
        box:BindUI()
    end
    return box.refs
end

local function makePopupBox(moduleName, frameName, cfg)
    local Box = module[moduleName] or {}
    module[moduleName] = Box
    Box._ui = Box._ui or {
        Loaded = false,
        Bound = false,
        Localized = false,
        Dirty = true,
        Reason = nil,
        FrameName = nil,
    }
    local BoxUI = Box._ui
    local getFrame = makeModuleFrameGetter(Box, frameName)
    local suffixes = cfg.refSuffixes
    local saveRef, cancelRef = cfg.saveRef, cfg.cancelRef or "cancelBtn"
    local enterRefs = cfg.enterRefs or {}
    local localizeMap = cfg.localizeMap
    local onShow, onHide = cfg.onShow, cfg.onHide

    function Box.AcquireRefs(frame)
        local refs = {}
        for i = 1, #suffixes do
            local s = suffixes[i]
            refs[s:sub(1, 1):lower() .. s:sub(2)] = Frames.GetRef(frame, s)
        end
        return refs
    end

    local function bindHandlers(_, frame, refs)
        if not frame or frame._krtBound then
            return
        end
        if refs[saveRef] then
            Frames.SetScriptSafely(refs[saveRef], "OnClick", function()
                Box._doSave()
            end)
        end
        if refs[cancelRef] then
            Frames.SetScriptSafely(refs[cancelRef], "OnClick", function()
                Box:Hide()
            end)
        end
        for i = 1, #enterRefs do
            if refs[enterRefs[i]] then
                Frames.SetScriptSafely(refs[enterRefs[i]], "OnEnterPressed", function()
                    Box._doSave()
                end)
            end
        end
        frame._krtBound = true
    end

    function Box:LocalizeUI(_, _, refs)
        for key, text in pairs(localizeMap) do
            if refs[key] then
                refs[key]:SetText(text)
            end
        end
    end

    local function loadBoxFrame(frame)
        BoxUI.FrameName = Frames.BindModuleFrame(Box, frame, {
            enableDrag = true,
            hookOnShow = onShow and function()
                onShow(Box)
            end or nil,
            hookOnHide = onHide and function()
                onHide(Box)
            end or nil,
        }) or BoxUI.FrameName
        BoxUI.Loaded = BoxUI.FrameName ~= nil
    end
    Box._LoadFrame = loadBoxFrame

    local refreshFn = cfg.refresh
    UIScaffold.DefineModuleUi({
        module = Box,
        getFrame = getFrame,
        acquireRefs = Box.AcquireRefs,
        bind = bindHandlers,
        localize = function(fn, frame, refs)
            Box:LocalizeUI(fn, frame, refs)
        end,
        onLoad = function(frame)
            loadBoxFrame(frame)
            return BoxUI.FrameName
        end,
        refresh = refreshFn and function()
            refreshFn(Box)
        end or nil,
    })

    Box._doSave = function() end
    return Box, BoxUI
end

-- Add/edit boss popup (time/mode normalization).
do
    local Box, BoxUI = makePopupBox("BossBox", "KRTLoggerBossBox", {
        refSuffixes = { "Title", "Name", "Difficulty", "Time", "NameStr", "DifficultyStr", "TimeStr", "SaveBtn", "CancelBtn" },
        saveRef = "saveBtn",
        enterRefs = { "name", "difficulty", "time" },
        localizeMap = {
            nameStr = L.StrName,
            difficultyStr = L.StrDifficulty,
            timeStr = L.StrTime,
            saveBtn = L.BtnSave,
            cancelBtn = L.BtnCancel,
        },
        onShow = function(b)
            b:RequestRefresh("show")
        end,
        onHide = function(b)
            b:CancelAddEdit()
        end,
        refresh = function(b)
            b._refresh()
        end,
    })
    local Store = module.Store

    local isEdit = false
    local tooltipsBound = false
    local raidData, bossData, tempDate = {}, {}, {}
    local editBossNid

    -- Campi uniformi:
    --   bossData.time : timestamp
    --   bossData.mode : "h" | "n"
    fillBossBox = function()
        local rID, bID = module.selectedRaid, module.selectedBoss
        if not (rID and bID) then
            return
        end

        raidData = Store:GetRaid(rID)
        if not raidData then
            return
        end

        bossData = Store:GetBoss(raidData, bID)
        if not bossData then
            return
        end

        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        local timeBox = refs and refs.time
        local difficultyBox = refs and refs.difficulty
        if not (nameBox and timeBox and difficultyBox) then
            return
        end

        nameBox:SetText(bossData.name or "")

        local bossTime = bossData.time or time()
        local d = date("*t", bossTime)
        tempDate = { day = d.day, month = d.month, year = d.year, hour = d.hour, min = d.min }
        timeBox:SetText(("%02d:%02d"):format(tempDate.hour, tempDate.min))

        local mode = bossData.mode
        if not mode and bossData.difficulty then
            mode = (bossData.difficulty == 3 or bossData.difficulty == 4) and "h" or "n"
        end
        difficultyBox:SetText((mode == "h") and "h" or "n")

        editBossNid = bossData and bossData.bossNid or nil
        isEdit = true
        Box:Toggle()
    end

    Box._doSave = function()
        local rID = module.selectedRaid
        if not rID then
            return
        end

        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        local difficultyBox = refs and refs.difficulty
        local timeBox = refs and refs.time
        if not (nameBox and difficultyBox and timeBox) then
            return
        end

        local name = TrimText(nameBox:GetText())
        local modeT = NormalizeLower(difficultyBox:GetText())
        local bTime = TrimText(timeBox:GetText())

        name = (name == "") and GetTrashMobName() or name
        if not IsTrashMobName(name) and (modeT ~= "h" and modeT ~= "n") then
            addon:error(L.ErrBossDifficulty)
            return
        end

        local h, m = bTime:match("^(%d+):(%d+)$")
        h, m = tonumber(h), tonumber(m)
        if not (h and m and addon.WithinRange(h, 0, 23) and addon.WithinRange(m, 0, 59)) then
            addon:error(L.ErrBossTime)
            return
        end

        local _, month, day, year = CalendarGetDate()
        local killDate = { day = day, month = month, year = year, hour = h, min = m }
        local mode = (modeT == "h") and "h" or "n"

        local bossNid = isEdit and editBossNid or nil
        local savedNid = module.Actions:UpsertBossKill(rID, bossNid, name, time(killDate), mode)
        if not savedNid then
            return
        end

        Box:Hide()
        resetSelections()
        triggerSelectionEvent(module, "selectedRaid", "ui")
    end

    function Box:CancelAddEdit()
        local refs = ensurePopupRefs(Box)
        Frames.ResetEditBox(refs and refs.name)
        Frames.ResetEditBox(refs and refs.difficulty)
        Frames.ResetEditBox(refs and refs.time)
        isEdit, raidData, bossData, editBossNid = false, {}, {}, nil
        twipe(tempDate)
    end

    Box._refresh = function()
        local refs = ensurePopupRefs(Box)
        local title = refs and refs.title
        if not title then
            return
        end

        if not tooltipsBound then
            Frames.SetTooltip(refs.name, L.StrBossNameHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(refs.difficulty, L.StrBossDifficultyHelp, "ANCHOR_LEFT")
            Frames.SetTooltip(refs.time, L.StrBossTimeHelp, "ANCHOR_RIGHT")
            tooltipsBound = true
        end

        UIPrimitives.SetText(title, L.StrEditBoss, L.StrAddBoss, isEdit)
    end
end

-- Add attendee popup.
do
    local Box = makePopupBox("AttendeesBox", "KRTLoggerPlayerBox", {
        refSuffixes = { "Title", "NameStr", "AddBtn", "CancelBtn", "Name" },
        saveRef = "addBtn",
        enterRefs = { "name" },
        localizeMap = {
            title = L.StrAddPlayer,
            nameStr = L.StrName,
            addBtn = L.BtnAdd,
            cancelBtn = L.BtnCancel,
        },
        onShow = function(b)
            local refs = ensurePopupRefs(b)
            Frames.ResetEditBox(refs and refs.name)
        end,
        onHide = function(b)
            local refs = ensurePopupRefs(b)
            Frames.ResetEditBox(refs and refs.name)
        end,
    })

    Box._doSave = function()
        local rID, bID = module.selectedRaid, module.selectedBoss
        local refs = ensurePopupRefs(Box)
        local nameBox = refs and refs.name
        if not nameBox then
            return
        end
        local name = TrimText(nameBox:GetText())
        if module.Actions:AddBossAttendee(rID, bID, name) then
            Box:Toggle()
            triggerSelectionEvent(module, "selectedBoss")
        end
    end
end

local registry = addon.ModuleRegistry
if type(registry) == "table" and type(registry.AddModule) == "function" and type(registry.SetLoaded) == "function" then
    registry.AddModule("Controllers/Logger", {
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Colors",
            "Modules/Base64",
            "Modules/Sort",
            "Modules/Dataset/IgnoredMobs",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
            "Modules/UI/MultiSelect",
            "Services/Logger/Store",
            "Services/Logger/View",
            "Services/Logger/Export",
            "Services/Logger/Helpers",
            "Services/Logger/Actions",
        },
    })
    registry.SetLoaded("Controllers/Logger")
end
