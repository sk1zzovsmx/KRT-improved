--[[
    Features/Reserves.lua
]]

local addon = select(2, ...)
local feature = addon.Core.getFeatureShared()

local L = feature.L
local Diag = feature.Diag
local Utils = feature.Utils
local C = feature.C

local bindModuleRequestRefresh = feature.bindModuleRequestRefresh
local bindModuleToggleHide = feature.bindModuleToggleHide

local _G = _G
local tinsert, tconcat, twipe = table.insert, table.concat, table.wipe
local pairs, ipairs, type, next = pairs, ipairs, type, next
local format = string.format

local tostring, tonumber = tostring, tonumber

-- =========== Reserves Module  =========== --
-- Manages item reserves, import, and display.
do
    addon.Reserves = addon.Reserves or {}
    local module = addon.Reserves
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON

    -- ----- Internal state ----- --
    -- UI Elements
    local frameName
    local getFrame = Utils.makeFrameGetter("KRTReserveListFrame")
    local scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows, rowsByItemID = {}, {}

    -- State variables
    local localized = false
    local reservesData = {}
    local reservesByItemID = {}
    local reservesByItemPlayer = {}
    local playerItemsByName = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local importMode = nil -- 'multi' or 'plus'
    local pendingItemInfo = {}
    local pendingItemCount = 0
    local collapsedBossGroups = {}
    local grouped = {}
    local reserveRowStyle = {
        odd = { 0.04, 0.06, 0.09, 0.30 },
        even = { 0.08, 0.10, 0.14, 0.36 },
        separator = { 1.0, 1.0, 1.0, 0.10 },
    }

    -- ----- Private helpers ----- --

    local playerTextTemp = {}

    local function NormalizeImportMode(mode)
        return (mode == "plus") and "plus" or "multi"
    end

    local function ImportModeToOptionValue(mode)
        return (NormalizeImportMode(mode) == "plus") and 1 or 0
    end

    local function SetImportMode(mode, syncOptions)
        local resolved = NormalizeImportMode(mode)
        importMode = resolved

        if syncOptions ~= false then
            local value = ImportModeToOptionValue(resolved)
            Utils.setOption("srImportMode", value)
        end

        return importMode
    end

    local function MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if not itemId then return nil end
        local pending = pendingItemInfo[itemId]
        if not pending then
            pending = {
                nameReady = false,
                iconReady = false,
                name = nil,
                link = nil,
                icon = nil,
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            addon:debug(Diag.D.LogReservesTrackPending:format(itemId, pendingItemCount))
        end
        if type(name) == "string" and name ~= "" then
            pending.name = name
        end
        if type(link) == "string" and link ~= "" then
            pending.link = link
        end
        if type(icon) == "string" and icon ~= "" then
            pending.icon = icon
        end
        if hasName then
            pending.nameReady = true
        end
        if hasIcon then
            pending.iconReady = true
        end
        return pending
    end

    local function GetPendingItemInfo(pending)
        if not pending then return nil end
        return pending.name, pending.link, pending.icon
    end

    local function CompletePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then return end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        addon:debug(Diag.D.LogReservesItemReady:format(itemId, pendingItemCount))
        if pendingItemCount == 0 then
            addon:debug(Diag.D.LogReservesPendingComplete)
            module:RequestRefresh()
        end
    end

    -- SoftRes exports class names like "Warrior", "Death Knight", etc.
    -- Normalize them to WoW class tokens (e.g. "WARRIOR", "DEATHKNIGHT") so we can use C.CLASS_COLORS.
    local function NormalizeClassToken(className)
        if not className then return nil end
        local token = tostring(className):upper()
        token = token:gsub("%s+", ""):gsub("%-", "")
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then return token end
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then return token end
        return nil
    end

    local function GetClassColorStr(className)
        local token = NormalizeClassToken(className) or "UNKNOWN"
        if C and C.CLASS_COLORS and C.CLASS_COLORS[token] then
            return token, C.CLASS_COLORS[token]
        end
        local _, _, _, colorStr = addon.GetClassColor(token)
        return token, colorStr
    end

    local function ColorizeReserveName(itemId, playerName, className)
        if not playerName then return playerName end

        local cls = className
        if (not cls or cls == "") and itemId then
            local r = module:GetReserveEntryForItem(itemId, playerName)
            cls = r and r.class
        end
        if (not cls or cls == "") and addon.Raid and addon.Raid.GetPlayerClass then
            cls = addon.Raid:GetPlayerClass(playerName)
        end
        if not cls or cls == "" then return playerName end

        local _, colorStr = GetClassColorStr(cls)
        if colorStr and colorStr ~= "ffffffff" then
            return "|c" .. colorStr .. playerName .. "|r"
        end
        return playerName
    end

    local function AddReservePlayer(data, rOrName, countOverride)
        if not data.players then data.players = {} end
        if not data.playerCounts then data.playerCounts = {} end
        if not data.playerMeta then data.playerMeta = {} end

        local name, count, cls, plus
        if type(rOrName) == "table" then
            name = rOrName.player or "?"
            count = tonumber(rOrName.quantity) or 1
            cls = rOrName.class
            plus = tonumber(rOrName.plus) or 0
        else
            name = rOrName or "?"
            count = tonumber(countOverride) or 1
        end
        count = count or 1

        local existing = data.playerCounts[name]
        if existing then
            data.playerCounts[name] = existing + count
        else
            data.players[#data.players + 1] = name
            data.playerCounts[name] = count
        end

        local meta = data.playerMeta[name]
        if not meta then
            meta = { plus = 0, class = nil }
            data.playerMeta[name] = meta
        end
        if cls and cls ~= "" and (not meta.class or meta.class == "") then
            meta.class = cls
        end
        if plus and plus > (meta.plus or 0) then
            meta.plus = plus
        end
    end

    local function GetMetaForPlayer(metaByName, itemId, playerName)
        local meta = metaByName and metaByName[playerName]
        if meta and (meta.class or meta.plus) then return meta end

        -- Fallback: resolve from index (keeps compatibility even if meta isn't passed).
        if not meta then meta = { plus = 0, class = nil } end
        if itemId and playerName then
            local r = module:GetReserveEntryForItem(itemId, playerName)
            if r then
                if r.class and r.class ~= "" and (not meta.class or meta.class == "") then
                    meta.class = r.class
                end
                local p = tonumber(r.plus) or 0
                if p > (meta.plus or 0) then meta.plus = p end
            end
            if (not meta.class or meta.class == "") and addon.Raid and addon.Raid.GetPlayerClass then
                meta.class = addon.Raid:GetPlayerClass(playerName)
            end
        end
        return meta
    end

    -- Formats a single player token for display.
    -- useColor:
    --   true/nil -> UI rendering (class colors enabled)
    --   false    -> chat-safe rendering (no class color codes)
    local function FormatReservePlayerName(itemId, name, count, metaByName, useColor, showPlus, showMulti)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        local out
        if useColor == false then
            out = name
        else
            out = ColorizeReserveName(itemId, name, meta and meta.class)
        end

        if showMulti ~= false and module:IsMultiReserve() and count and count > 1 then
            out = out .. format(L.StrReserveCountSuffix, count)
        end

        if showPlus ~= false and module:IsPlusSystem() and itemId then
            local p = (meta and tonumber(meta.plus)) or module:GetPlusForItem(itemId, name) or 0
            if p and p > 0 then
                out = out .. format(" (P+%d)", p)
            end
        end

        return out
    end

    local function SortPlayersForDisplay(itemId, players, counts, metaByName)
        if not players then return end

        if module:IsPlusSystem() and itemId then
            table.sort(players, function(a, b)
                local am = GetMetaForPlayer(metaByName, itemId, a)
                local bm = GetMetaForPlayer(metaByName, itemId, b)
                local ap = (am and tonumber(am.plus)) or 0
                local bp = (bm and tonumber(bm.plus)) or 0
                if ap ~= bp then return ap > bp end
                return tostring(a) < tostring(b)
            end)
        elseif module:IsMultiReserve() and counts then
            -- Optional: show higher quantities first for readability.
            table.sort(players, function(a, b)
                local aq = counts[a] or 1
                local bq = counts[b] or 1
                if aq ~= bq then return aq > bq end
                return tostring(a) < tostring(b)
            end)
        end
    end

    local function BuildPlayerTokens(itemId, players, counts, metaByName, useColor, showPlus, showMulti)
        if not players then return {} end
        SortPlayersForDisplay(itemId, players, counts, metaByName)
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] =
                FormatReservePlayerName(
                    itemId,
                    name,
                    counts and counts[name] or 1,
                    metaByName,
                    useColor,
                    showPlus,
                    showMulti
                )
        end
        return playerTextTemp
    end

    -- How many player tokens we show inline in the Reserve List row before truncating.
    -- Long lists are rendered in a dedicated tooltip on the players line.
    local RESERVE_ROW_MAX_PLAYERS_INLINE = 6

    local function FormatReservePlayerNameBase(itemId, name, metaByName)
        local meta = GetMetaForPlayer(metaByName, itemId, name)
        return ColorizeReserveName(itemId, name, meta and meta.class)
    end

    local function BuildPlayersTooltipLines(itemId, players, counts, metaByName, shownCount, hiddenCount)
        local lines = {}
        local total = players and #players or 0
        lines[#lines + 1] = format(L.StrReservesTooltipTotal, total)
        if hiddenCount and hiddenCount > 0 and shownCount and shownCount > 0 then
            lines[#lines + 1] = format(L.StrReservesTooltipShownHidden, shownCount, hiddenCount)
        end

        if not players or total == 0 then
            return lines
        end

        if module:IsPlusSystem() and itemId then
            -- Group by plus value (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local meta = GetMetaForPlayer(metaByName, itemId, name)
                local p = (meta and tonumber(meta.plus)) or 0
                if groups[p] == nil then
                    groups[p] = {}
                    keys[#keys + 1] = p
                end
                groups[p][#groups[p] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
            for i = 1, #keys do
                local p = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipPlus, p, tconcat(groups[p], ", "))
            end
        elseif module:IsMultiReserve() and counts then
            -- Group by quantity (desc)
            local groups, keys = {}, {}
            for i = 1, #players do
                local name = players[i]
                local q = counts[name] or 1
                if groups[q] == nil then
                    groups[q] = {}
                    keys[#keys + 1] = q
                end
                groups[q][#groups[q] + 1] = FormatReservePlayerNameBase(itemId, name, metaByName)
            end
            table.sort(keys, function(a, b) return a > b end)
            for i = 1, #keys do
                local q = keys[i]
                lines[#lines + 1] = format(L.StrReservesTooltipQuantity, q, tconcat(groups[q], ", "))
            end
        else
            -- Fallback: just list names
            local names = {}
            for i = 1, #players do
                names[i] = FormatReservePlayerNameBase(itemId, players[i], metaByName)
            end
            lines[#lines + 1] = tconcat(names, ", ")
        end

        return lines
    end

    local function BuildPlayersText(itemId, players, counts, metaByName)
        if not players then return "", {}, "" end
        BuildPlayerTokens(itemId, players, counts, metaByName)
        local total = #playerTextTemp
        local shown = total
        if RESERVE_ROW_MAX_PLAYERS_INLINE and RESERVE_ROW_MAX_PLAYERS_INLINE > 0 then
            shown = math.min(total, RESERVE_ROW_MAX_PLAYERS_INLINE)
        end
        local hidden = total - shown
        local shortText = tconcat(playerTextTemp, ", ", 1, shown)
        if hidden > 0 then
            shortText = shortText .. format(L.StrReservesPlayersHiddenSuffix, hidden)
        end
        local fullText = tconcat(playerTextTemp, ", ")
        local tooltipLines = BuildPlayersTooltipLines(itemId, players, counts, metaByName, shown, hidden)
        return shortText, tooltipLines, fullText
    end

    local function GetReserveSource(source)
        if source and source ~= "" then
            return source
        end
        return L.StrUnknown
    end

    local function FormatReserveItemIdLabel(itemId)
        return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
    end

    -- Kept for potential future tooltip/source variants.
    local function FormatReserveDroppedBy(source)
        if not source or source == "" then return nil end
        return format(L.StrReservesTooltipDroppedBy, source)
    end

    local function FormatReserveItemFallback(itemId)
        return format(L.StrReservesItemFallback, tostring(itemId or "?"))
    end

    local function UpdateDisplayEntryForItem(itemId)
        if not itemId then return end
        reservesDirty = true

        local groupedBySource = {}
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" then
                    local source = GetReserveSource(r.source)
                    local bySource = groupedBySource[source]
                    if not bySource then
                        bySource = {}
                        groupedBySource[source] = bySource
                        if collapsedBossGroups[source] == nil then
                            collapsedBossGroups[source] = false
                        end
                    end
                    local data = bySource[itemId]
                    if not data then
                        data = {
                            itemId = itemId,
                            itemLink = r.itemLink,
                            itemName = r.itemName,
                            itemIcon = r.itemIcon,
                            source = source,
                            players = {},
                            playerCounts = {},
                            playerMeta = {},
                        }
                        bySource[itemId] = data
                    end
                    AddReservePlayer(data, r)
                end
            end
        end

        local existing = {}
        local remaining = {}
        for i = 1, #reservesDisplayList do
            local data = reservesDisplayList[i]
            if data and data.itemId == itemId then
                existing[#existing + 1] = data
            else
                remaining[#remaining + 1] = data
            end
        end

        local reused = 0
        for source, byQty in pairs(groupedBySource) do
            for _, data in pairs(byQty) do
                reused = reused + 1
                local target = existing[reused]
                if target then
                    target.itemId = itemId
                    target.itemLink = data.itemLink
                    target.itemName = data.itemName
                    target.itemIcon = data.itemIcon
                    target.source = source
                    target.players = target.players or {}
                    target.playerCounts = target.playerCounts or {}
                    target.playerMeta = target.playerMeta or {}
                    twipe(target.players)
                    twipe(target.playerCounts)
                    twipe(target.playerMeta)
                    for i = 1, #data.players do
                        local name = data.players[i]
                        target.players[i] = name
                        target.playerCounts[name] = data.playerCounts[name]
                    end
                    if data.playerMeta then
                        for n, m in pairs(data.playerMeta) do
                            local tm = target.playerMeta[n]
                            if not tm then
                                tm = {}; target.playerMeta[n] = tm
                            end
                            tm.plus = (m and tonumber(m.plus)) or 0
                            tm.class = m and m.class or tm.class
                        end
                    end
                    target.playersText, target.playersTooltipLines, target.playersTextFull =
                        BuildPlayersText(
                            itemId,
                            target.players,
                            target.playerCounts,
                            target.playerMeta
                        )
                    target.players = nil
                    target.playerCounts = nil
                    target.playerMeta = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText, data.playersTooltipLines, data.playersTextFull =
                        BuildPlayersText(
                            data.itemId,
                            data.players,
                            data.playerCounts,
                            data.playerMeta
                        )
                    data.players = nil
                    data.playerCounts = nil
                    data.playerMeta = nil
                    remaining[#remaining + 1] = data
                end
            end
        end

        twipe(reservesDisplayList)
        for i = 1, #remaining do
            reservesDisplayList[i] = remaining[i]
        end
    end

    local function RebuildIndex()
        twipe(reservesByItemID)
        twipe(reservesByItemPlayer)
        twipe(playerItemsByName)
        reservesDirty = true

        -- Build fast lookup indices
        for playerKey, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = player.original or "?"
                local normalizedPlayer = Utils.normalizeLower(playerName, true) or playerKey
                playerItemsByName[normalizedPlayer] = playerItemsByName[normalizedPlayer] or {}

                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = r.player or playerName
                        local itemId = r.rawID

                        local list = reservesByItemID[itemId]
                        if not list then
                            list = {}
                            reservesByItemID[itemId] = list
                        end
                        list[#list + 1] = r

                        local byP = reservesByItemPlayer[itemId]
                        if not byP then
                            byP = {}
                            reservesByItemPlayer[itemId] = byP
                        end
                        byP[normalizedPlayer] = r
                        playerItemsByName[normalizedPlayer][itemId] = true
                    end
                end
            end
        end

        twipe(reservesDisplayList)
        twipe(grouped)
        for itemId, list in pairs(reservesByItemID) do
            if type(list) == "table" then
                for i = 1, #list do
                    local r = list[i]
                    if type(r) == "table" then
                        local source = GetReserveSource(r.source)

                        local bySource = grouped[source]
                        if not bySource then
                            bySource = {}
                            grouped[source] = bySource
                            if collapsedBossGroups[source] == nil then
                                collapsedBossGroups[source] = false
                            end
                        end

                        local data = bySource[itemId]
                        if not data then
                            data = {
                                itemId = itemId,
                                itemLink = r.itemLink,
                                itemName = r.itemName,
                                itemIcon = r.itemIcon,
                                source = source,
                                players = {},
                                playerCounts = {},
                                playerMeta = {},
                            }
                            bySource[itemId] = data
                        end

                        AddReservePlayer(data, r)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText, data.playersTooltipLines, data.playersTextFull =
                    BuildPlayersText(
                        data.itemId,
                        data.players,
                        data.playerCounts,
                        data.playerMeta
                    )
                data.players = nil
                data.playerCounts = nil
                data.playerMeta = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    local function SetupReserveRowTooltip(row)
        if not row then return end

        local function HideTooltip()
            GameTooltip:Hide()
        end

        local function ShowItemTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = row._itemLink
            if (not link or link == "") and row._itemId then
                link = "item:" .. tostring(row._itemId)
            end
            if link then
                GameTooltip:SetHyperlink(link)
            elseif row._tooltipTitle then
                GameTooltip:SetText(row._tooltipTitle, 1, 1, 1)
            end
            GameTooltip:Show()
        end

        local function ShowPlayersTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row._tooltipTitle or L.StrReservesTooltipTitle, 1, 1, 1)
            local lines = row._playersTooltipLines
            if type(lines) == "table" then
                for i = 1, #lines do
                    GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true)
                end
            elseif row._playersTextFull and row._playersTextFull ~= "" then
                GameTooltip:AddLine(row._playersTextFull, 0.9, 0.9, 0.9, true)
            end
            GameTooltip:Show()
        end

        -- Icon = item tooltip (keeps the classic behavior)
        if row.iconBtn then
            row.iconBtn:SetScript("OnEnter", ShowItemTooltip)
            row.iconBtn:SetScript("OnLeave", HideTooltip)
        end

        -- Two tooltips (no XML changes):
        -- * Item tooltip on the TOP line (item name)
        -- * Full players list tooltip on the BOTTOM line (players)
        if row.textBlock then
            row.textBlock:EnableMouse(false)

            if not row._nameHotspot then
                local hs = CreateFrame("Button", nil, row.textBlock)
                hs:ClearAllPoints()
                hs:SetPoint("TOPLEFT", row.textBlock, "TOPLEFT", 0, 0)
                hs:SetHeight(16)
                hs:SetWidth(row.textBlock:GetWidth() > 0 and row.textBlock:GetWidth() or 200)
                hs:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
                hs:EnableMouse(true)
                hs:SetScript("OnEnter", ShowItemTooltip)
                hs:SetScript("OnLeave", HideTooltip)
                row._nameHotspot = hs
            end

            if not row._playersHotspot then
                local hs = CreateFrame("Button", nil, row.textBlock)
                hs:ClearAllPoints()
                hs:SetPoint("BOTTOMLEFT", row.textBlock, "BOTTOMLEFT", 0, 0)
                hs:SetHeight(16)
                hs:SetWidth(row.textBlock:GetWidth() > 0 and row.textBlock:GetWidth() or 200)
                hs:SetFrameLevel(row.textBlock:GetFrameLevel() + 2)
                hs:EnableMouse(true)
                hs:SetScript("OnEnter", ShowPlayersTooltip)
                hs:SetScript("OnLeave", HideTooltip)
                row._playersHotspot = hs
            end
        end
    end

    local function Clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    -- Limit the hover area (hotspots) to the actual rendered text width,
    -- instead of the full row width.
    local function UpdateReserveRowHotspots(row)
        if not row or not row.textBlock then return end
        local maxW = row.textBlock:GetWidth() or 0
        if maxW <= 0 then maxW = 200 end
        local pad = 8

        if row._nameHotspot and row.nameText then
            local t = row.nameText:GetText() or ""
            if t ~= "" then
                local w = row.nameText.GetStringWidth and row.nameText:GetStringWidth() or 0
                row._nameHotspot:SetWidth(Clamp(w + pad, 2, maxW))
                row._nameHotspot:EnableMouse(true)
            else
                row._nameHotspot:SetWidth(2)
                row._nameHotspot:EnableMouse(false)
            end
        end

        if row._playersHotspot and row.playerText then
            local t = row.playerText:GetText() or ""
            if t ~= "" then
                local w = row.playerText.GetStringWidth and row.playerText:GetStringWidth() or 0
                row._playersHotspot:SetWidth(Clamp(w + pad, 2, maxW))
                row._playersHotspot:EnableMouse(true)
            else
                row._playersHotspot:SetWidth(2)
                row._playersHotspot:EnableMouse(false)
            end
        end
    end

    local function ApplyReserveRowData(row, info, index, isFirstInGroup)
        if not row or not info then return end
        row._itemId = info.itemId
        row._itemLink = info.itemLink
        row._itemName = info.itemName
        row._source = info.source
        row._tooltipTitle = info.itemLink or info.itemName or FormatReserveItemIdLabel(info.itemId)
        row._tooltipSource = FormatReserveDroppedBy(info.source)
        row._playersTooltipLines = info.playersTooltipLines
        row._playersTextFull = info.playersTextFull or info.playersText

        local isEvenRow = (index % 2 == 0)
        if row.background then
            local bg = isEvenRow and reserveRowStyle.even or reserveRowStyle.odd
            row.background:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
        end
        if row.separator then
            local sepAlpha = isEvenRow and 0.1 or reserveRowStyle.separator[4]
            row.separator:SetVertexColor(
                reserveRowStyle.separator[1],
                reserveRowStyle.separator[2],
                reserveRowStyle.separator[3],
                sepAlpha
            )
            row.separator:Show()
        end
        if row.topSeparator then
            row.topSeparator:SetVertexColor(
                reserveRowStyle.separator[1],
                reserveRowStyle.separator[2],
                reserveRowStyle.separator[3],
                reserveRowStyle.separator[4]
            )
            if isFirstInGroup then
                row.topSeparator:Show()
            else
                row.topSeparator:Hide()
            end
        end

        if row.iconTexture then
            local icon = info.itemIcon
            if not icon and info.itemId then
                local fetchedIcon = GetItemIcon(info.itemId)
                if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                    info.itemIcon = fetchedIcon
                    icon = fetchedIcon
                end
            end
            if type(icon) ~= "string" or icon == "" then
                icon = fallbackIcon
                info.itemIcon = icon
            end
            row.iconTexture:SetTexture(icon)
            row.iconTexture:Show()
        end

        if row.nameText then
            row.nameText:SetText(info.itemLink or info.itemName or FormatReserveItemFallback(info.itemId))
        end

        if row.playerText then
            row.playerText:SetText(info.playersText or "")
        end
        if row.quantityText then
            row.quantityText:Hide()
        end

        UpdateReserveRowHotspots(row)
    end

    local function ReserveHeaderOnClick(self)
        local source = self and self._source
        if not source then return end
        collapsedBossGroups[source] = not collapsedBossGroups[source]
        addon:debug(Diag.D.LogReservesToggleCollapse:format(source, tostring(collapsedBossGroups[source])))
        module:RequestRefresh()
    end

    -- ----- Public methods ----- --

    -- Local functions
    local LocalizeUIFrame
    local UpdateUIFrame
    local RenderReserveListUI

    -- ----- Saved Data Management ----- --

    function module:Save()
        RebuildIndex()
        addon:debug(Diag.D.LogReservesSaveEntries:format(addon.tLength(reservesData)))
        local saved = {}
        addon.tCopy(saved, reservesData)
        KRT_Reserves = saved
    end

    function module:Load()
        addon:debug(Diag.D.LogReservesLoadData:format(tostring(KRT_Reserves ~= nil)))
        twipe(reservesData)
        if KRT_Reserves then
            addon.tCopy(reservesData, KRT_Reserves)
        end

        -- Infer import mode from saved data when possible.
        -- If we detect any multi-item or quantity>1 entries, treat it as Multi-reserve.
        importMode = nil
        local inferred
        for _, p in pairs(reservesData) do
            if type(p) == "table" and type(p.reserves) == "table" then
                if #p.reserves > 1 then
                    inferred = "multi"
                    break
                end
                for i = 1, #p.reserves do
                    local r = p.reserves[i]
                    local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                    if qty and qty > 1 then
                        inferred = "multi"
                        break
                    end
                end
            end
            if inferred == "multi" then break end
        end
        if not inferred then
            local v = addon.options and addon.options.srImportMode
            inferred = (v == 1) and "plus" or "multi"
        end
        SetImportMode(inferred, true)

        RebuildIndex()
    end

    function module:ResetSaved()
        addon:debug(Diag.D.LogReservesResetSaved)
        KRT_Reserves = nil
        twipe(reservesData)
        RebuildIndex()
        self:Hide()
        self:RequestRefresh()
        Utils.triggerEvent("ReservesDataChanged", "clear")
        addon:info(L.StrReserveListCleared)
    end

    function module:HasData()
        return next(reservesData) ~= nil
    end

    function module:HasItemReserves(itemId)
        if not itemId then return false end
        local list = reservesByItemID[itemId]
        return type(list) == "table" and #list > 0
    end

    -- ----- UI Window Management ----- --

    -- Initialize UI controller for Toggle/Hide.
    Utils.bootstrapModuleUi(module, getFrame, function()
        module:RequestRefresh()
    end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    function module:OnLoad(frame)
        addon:debug(Diag.D.LogReservesFrameLoaded)
        frameName = Utils.initModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                addon:debug(Diag.D.LogReservesShowWindow)
            end,
            hookOnHide = function()
                addon:debug(Diag.D.LogReservesHideWindow)
            end,
        })
        if not frameName then return end

        scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
        scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

        local buttons = {
            CloseButton = "Hide",
            ClearButton = "ResetSaved",
            QueryButton = "QueryMissingItems",
        }
        for suff, method in pairs(buttons) do
            local btn = _G["KRTReserveListFrame" .. suff]
            if btn and self[method] then
                btn:SetScript("OnClick", function() self[method](self) end)
                addon:debug(Diag.D.LogReservesBindButton:format(suff, method))
            end
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug(Diag.D.LogReservesItemInfoReceived:format(itemId))
            local pending = pendingItemInfo[itemId]
            if not pending then return end

            local name, link, icon = GetPendingItemInfo(pending)
            local hasName = type(name) == "string" and name ~= ""
                and type(link) == "string" and link ~= ""
            local hasIcon = type(icon) == "string" and icon ~= ""

            if not hasName then
                local fetchedName, fetchedLink, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
                if type(fetchedName) == "string" and fetchedName ~= "" then
                    name = fetchedName
                end
                if type(fetchedLink) == "string" and fetchedLink ~= "" then
                    link = fetchedLink
                end
                if type(tex) == "string" and tex ~= "" then
                    icon = icon or tex
                end
            end

            if not hasIcon then
                local fetchedIcon = GetItemIcon(itemId)
                if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                    icon = fetchedIcon
                end
            end

            hasName = type(name) == "string" and name ~= ""
                and type(link) == "string" and link ~= ""
            hasIcon = type(icon) == "string" and icon ~= ""

            if hasName then
                addon:debug(Diag.D.LogReservesUpdateItemData:format(link))
                self:UpdateReserveItemData(itemId, name, link, icon)
            else
                addon:debug(Diag.D.LogReservesItemInfoMissing:format(itemId))
            end
            MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
            if hasName and hasIcon then
                addon:debug(Diag.D.LogSRItemInfoResolved:format(itemId, tostring(link)))
                CompletePendingItem(itemId)
            else
                addon:debug(Diag.D.LogReservesItemInfoPending:format(itemId))
                self:QueryItemInfo(itemId)
            end
        end)
    end

    -- ----- Localization and UI Update ----- --

    function LocalizeUIFrame()
        if localized then
            addon:debug(Diag.D.LogReservesUIAlreadyLocalized)
            return
        end
        if frameName then
            Utils.setFrameTitle(frameName, L.StrRaidReserves)
            addon:debug(Diag.D.LogReservesUILocalized:format(L.StrRaidReserves))
        end
        local clearButton = frameName and _G[frameName .. "ClearButton"]
        if clearButton then
            clearButton:SetText(L.BtnClearReserves)
        end
        local queryButton = frameName and _G[frameName .. "QueryButton"]
        if queryButton then
            queryButton:SetText(L.BtnQueryItem)
        end
        local closeButton = frameName and _G[frameName .. "CloseButton"]
        if closeButton then
            closeButton:SetText(L.BtnClose)
        end
        localized = true
    end

    -- Update UI Frame:
    function UpdateUIFrame()
        LocalizeUIFrame()
        local hasData = module:HasData()
        local clearButton = _G[frameName .. "ClearButton"]
        if clearButton then
            if hasData then
                clearButton:Show()
                Utils.enableDisable(clearButton, true)
            else
                clearButton:Hide()
            end
        end
        local queryButton = _G[frameName .. "QueryButton"]
        if queryButton then
            Utils.enableDisable(queryButton, hasData)
        end
    end

    function module:Refresh()
        if UpdateUIFrame then UpdateUIFrame() end
        local frame = getFrame()
        if frame and RenderReserveListUI then
            RenderReserveListUI()
        end
    end

    -- ----- Reserve Data Handling ----- --

    function module:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = Utils.normalizeLower(playerName)
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if reserve then
            addon:debug(Diag.D.LogReservesPlayerFound:format(playerName, tostring(reserve)))
        else
            addon:debug(Diag.D.LogReservesPlayerNotFound:format(playerName))
        end

        return reserve
    end

    -- Get all reserves:
    function module:GetAllReserves()
        addon:debug(Diag.D.LogReservesFetchAll:format(addon.tLength(reservesData)))
        return reservesData
    end

    -- Parse imported text (SoftRes CSV)
    -- mode: "multi" (multi-reserve enabled; Plus ignored) or "plus" (priority; requires 1 item per player)
    function module:GetImportMode()
        if importMode == nil then
            local v = addon.options and addon.options.srImportMode
            SetImportMode((v == 1) and "plus" or "multi", false)
        end
        return importMode
    end

    function module:SetImportMode(mode, syncOptions)
        return SetImportMode(mode, syncOptions)
    end

    function module:IsPlusSystem()
        return self:GetImportMode() == "plus"
    end

    function module:IsMultiReserve()
        return self:GetImportMode() == "multi"
    end

    -- Strategy objects to keep Plus/Multi behaviors isolated.
    local importStrategies = {}

    local function cleanCSVField(field)
        if not field then return nil end
        return Utils.trimText(field:gsub('^"(.-)"$', '%1'), true)
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
            elseif ch == ',' and not inQuotes then
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
                map[Utils.normalizeLower(key)] = i
            end
        end
        -- Consider it a header only if it includes key columns.
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

    local function parseCSVRows(csv)
        local rows = {}
        local headerMap = nil
        local firstLine = true

        for line in csv:gmatch("[^\n]+") do
            line = line:gsub("\r$", "")
            if firstLine then
                firstLine = false
                local maybeHeader = splitCSVLine(line)
                local map, isHeader = buildHeaderMap(maybeHeader)
                if isHeader then
                    headerMap = map
                else
                    -- No header detected: treat first line as data
                    local fields     = maybeHeader

                    local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                    local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                    local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                    local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                    local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                    local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                    local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                    local itemId     = tonumber(itemIdStr)
                    local playerKey  = Utils.normalizeLower(playerName, true)
                    if itemId and playerKey then
                        rows[#rows + 1] = {
                            itemId = itemId,
                            player = playerName,
                            playerKey = playerKey,
                            source = source ~= "" and source or nil,
                            class = class ~= "" and class or nil,
                            spec = spec ~= "" and spec or nil,
                            note = note ~= "" and note or nil,
                            plus = tonumber(plus) or 0,
                        }
                    end
                end
            else
                local fields     = splitCSVLine(line)

                local itemIdStr  = cleanCSVField(getField(fields, headerMap, "itemid", 2))
                local source     = cleanCSVField(getField(fields, headerMap, "from", 3))
                local playerName = cleanCSVField(getField(fields, headerMap, "name", 4))
                local class      = cleanCSVField(getField(fields, headerMap, "class", 5))
                local spec       = cleanCSVField(getField(fields, headerMap, "spec", 6))
                local note       = cleanCSVField(getField(fields, headerMap, "note", 7))
                local plus       = cleanCSVField(getField(fields, headerMap, "plus", 8))

                local itemId     = tonumber(itemIdStr)
                local playerKey  = Utils.normalizeLower(playerName, true)

                if itemId and playerKey then
                    rows[#rows + 1] = {
                        itemId = itemId,
                        player = playerName,
                        playerKey = playerKey,
                        source = source ~= "" and source or nil,
                        class = class ~= "" and class or nil,
                        spec = spec ~= "" and spec or nil,
                        note = note ~= "" and note or nil,
                        plus = tonumber(plus) or 0,
                    }
                else
                    addon:debug(Diag.D.LogSRParseSkippedLine:format(tostring(line)))
                end
            end
        end

        return rows
    end
    local function validatePlusRows(rows)
        -- Plus System requires exactly 1 reserve entry per player (SoftRes set to 1 SR per player).
        -- If a player appears more than once (even for the same item), it means a multi-reserve CSV was pasted.
        local seen = {}
        for i = 1, #rows do
            local row = rows[i]
            local rec = seen[row.playerKey]
            if not rec then
                seen[row.playerKey] = { itemId = row.itemId, player = row.player, count = 1 }
            else
                rec.count = (rec.count or 1) + 1
                if rec.itemId ~= row.itemId then
                    return false, "CSV_WRONG_FOR_PLUS", {
                        player = row.player,
                        reason = "multi_item",
                        first = rec.itemId,
                        second = row.itemId,
                        count = rec.count,
                    }
                end
                return false, "CSV_WRONG_FOR_PLUS", {
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
                container = { original = row.player, reserves = {} }
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
                    player = row.player,
                }
                idx[row.itemId] = entry
                container.reserves[#container.reserves + 1] = entry
            end
        end

        return newReservesData
    end

    importStrategies.multi = {
        id = "multi",
        Validate = function(rows) return true end,
        Aggregate = function(rows) return aggregateRows(rows, true) end,
    }

    importStrategies.plus = {
        id = "plus",
        Validate = validatePlusRows,
        Aggregate = function(rows) return aggregateRows(rows, false) end,
    }

    function module:GetImportStrategy(mode)
        mode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        return importStrategies[mode] or importStrategies.multi
    end

    function module:ParseCSV(csv, mode)
        if type(csv) ~= "string" or not csv:match("%S") then
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0, "EMPTY"
        end

        mode = (mode == "plus" or mode == "multi") and mode or self:GetImportMode()
        local strat = self:GetImportStrategy(mode)

        addon:debug(Diag.D.LogReservesParseStart)

        -- Transactional parse flow: parse -> validate -> aggregate -> commit.
        local rows = parseCSVRows(csv)
        if not rows or #rows == 0 then
            addon:warn(L.WarnNoValidRows)
            return false, 0, "NO_ROWS"
        end

        local ok, errCode, errData = strat.Validate(rows)
        if not ok then
            addon:debug(Diag.D.LogReservesImportWrongModePlus
                and Diag.D.LogReservesImportWrongModePlus:format(tostring(errData and errData.player))
                or ("Wrong CSV for Plus System: " .. tostring(errData and errData.player)))
            return false, 0, errCode or "CSV_INVALID", errData
        end

        local newReservesData = strat.Aggregate(rows)

        -- Commit
        reservesData = newReservesData
        SetImportMode(mode, true)
        self:Save()

        local nPlayers = addon.tLength(reservesData)
        addon:debug(Diag.D.LogReservesParseComplete:format(nPlayers))
        addon:info(format(L.SuccessReservesParsed, tostring(nPlayers)))
        self:RequestRefresh()
        Utils.triggerEvent("ReservesDataChanged", "import", nPlayers, mode)
        return true, nPlayers
    end

    -- ----- Item Info Querying ----- --
    function module:QueryItemInfo(itemId)
        if not itemId then return end
        addon:debug(Diag.D.LogReservesQueryItemInfo:format(itemId))
        local pending = pendingItemInfo[itemId]
        local name, link, icon = GetPendingItemInfo(pending)
        local hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        local hasIcon = type(icon) == "string" and icon ~= ""

        if not hasName then
            local fetchedName, fetchedLink, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
            if type(fetchedName) == "string" and fetchedName ~= "" then
                name = fetchedName
            end
            if type(fetchedLink) == "string" and fetchedLink ~= "" then
                link = fetchedLink
            end
            if type(tex) == "string" and tex ~= "" then
                icon = icon or tex
            end
        end

        if not hasIcon then
            local fetchedIcon = GetItemIcon(itemId)
            if type(fetchedIcon) == "string" and fetchedIcon ~= "" then
                icon = fetchedIcon
            end
        end

        hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        MarkPendingItem(itemId, hasName, hasIcon, name, link, icon)
        if hasName and hasIcon then
            addon:debug(Diag.D.LogReservesItemInfoReady:format(itemId, name))
            CompletePendingItem(itemId)
            return true
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
        addon:debug(Diag.D.LogReservesItemInfoPendingQuery:format(itemId))
        return false
    end

    -- Query all missing items for reserves
    function module:QueryMissingItems(silent)
        local seen = {}
        local count = 0
        local updated = false
        addon:debug(Diag.D.LogReservesQueryMissingItems)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for _, r in ipairs(player.reserves) do
                    local itemId = r.rawID
                    if itemId and not seen[itemId] and (not r.itemLink or not r.itemIcon) then
                        seen[itemId] = true
                        if not self:QueryItemInfo(itemId) then
                            count = count + 1
                        else
                            updated = true
                        end
                    end
                end
            end
        end
        if updated then
            self:RequestRefresh()
        end
        if not silent then
            if count > 0 then
                addon:info(L.MsgReserveItemsRequested, count)
            else
                addon:info(L.MsgReserveItemsReady)
            end
        end
        addon:debug(Diag.D.LogReservesMissingItems:format(count))
        addon:debug(Diag.D.LogSRQueryMissingItems:format(tostring(updated), count))
    end

    -- Update reserve item data
    function module:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
        if not itemId then return end
        local icon = itemIcon
        if (type(icon) ~= "string" or icon == "") and itemName then
            icon = fallbackIcon
        end
        reservesDirty = true

        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                if type(r) == "table" and r.rawID == itemId then
                    r.itemName = itemName
                    r.itemLink = itemLink
                    r.itemIcon = icon
                end
            end
        else
            -- Fallback: scan all players (should be rare if index is up to date)
            for _, player in pairs(reservesData) do
                if type(player) == "table" and type(player.reserves) == "table" then
                    for i = 1, #player.reserves do
                        local r = player.reserves[i]
                        if type(r) == "table" and r.rawID == itemId then
                            r.itemName = itemName
                            r.itemLink = itemLink
                            r.itemIcon = icon
                        end
                    end
                end
            end
        end

        UpdateDisplayEntryForItem(itemId)

        local rows = rowsByItemID[itemId]
        if not rows then return end
        for i = 1, #rows do
            local row = rows[i]
            row._itemId = itemId
            row._itemLink = itemLink
            row._itemName = itemName
            row._tooltipTitle = itemLink or itemName or FormatReserveItemIdLabel(itemId)
            row._tooltipSource = FormatReserveDroppedBy(row._source)
            if row.iconTexture then
                local resolvedIcon = icon
                if type(resolvedIcon) ~= "string" or resolvedIcon == "" then
                    resolvedIcon = fallbackIcon
                end
                row.iconTexture:SetTexture(resolvedIcon)
                row.iconTexture:Show()
            end
            if row.nameText then
                row.nameText:SetText(itemLink or itemName or FormatReserveItemFallback(itemId))
            end
        end
    end

    -- Get reserve count for a specific item for a player
    function module:GetReserveCountForItem(itemId, playerName)
        local r = self:GetReserveEntryForItem(itemId, playerName)
        if not r then return 0 end
        return tonumber(r.quantity) or 1
    end

    -- Gets the reserve entry table for a specific item for a player (or nil).
    function module:GetReserveEntryForItem(itemId, playerName)
        if not itemId or not playerName then return nil end
        local playerKey = Utils.normalizeLower(playerName, true)
        if not playerKey then return nil end

        local byP = reservesByItemPlayer[itemId]
        if type(byP) == "table" then
            local r = byP[playerKey]
            if r then return r end
        end

        -- Fallback (should be rare if indices are up to date)
        local entry = reservesData[playerKey]
        if not entry then return nil end
        for _, r in ipairs(entry.reserves or {}) do
            if r and r.rawID == itemId then
                return r
            end
        end
        return nil
    end

    -- Gets the "Plus" value for a reserved item for a player (0 if missing).
    function module:GetPlusForItem(itemId, playerName)
        -- Plus values are meaningful only in Plus System mode.
        if self:GetImportMode() ~= "plus" then return 0 end
        local r = self:GetReserveEntryForItem(itemId, playerName)
        return (r and tonumber(r.plus)) or 0
    end

    -- Returns true if the item has any multi-reserve entry (quantity > 1).
    -- When true, SR "Plus priority" should be disabled for this item.
    function module:HasMultiReserveForItem(itemId)
        if self:GetImportMode() ~= "multi" then return false end
        if not itemId then return false end
        local list = reservesByItemID[itemId]
        if type(list) == "table" then
            for i = 1, #list do
                local r = list[i]
                local qty = (type(r) == "table" and tonumber(r.quantity)) or 1
                if (qty or 1) > 1 then
                    return true
                end
            end
            return false
        end

        -- Fallback: scan all players (should be rare if index is up to date)
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID == itemId then
                        local qty = tonumber(r.quantity) or 1
                        if qty > 1 then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- ----- UI Display ----- --

    function RenderReserveListUI()
        local frame = getFrame()
        if not frame or not scrollChild then return end
        module.frame = frame

        -- Hide and clear old rows
        for i = 1, #reserveItemRows do
            reserveItemRows[i]:Hide()
        end
        twipe(reserveItemRows)
        twipe(rowsByItemID)

        -- Hide and clear old headers
        for i = 1, #reserveHeaders do
            reserveHeaders[i]:Hide()
        end
        twipe(reserveHeaders)

        if reservesDirty then
            table.sort(reservesDisplayList, function(a, b)
                if a.source ~= b.source then return a.source < b.source end
                if a.itemId ~= b.itemId then return a.itemId < b.itemId end
                return false
            end)
            reservesDirty = false
        end

        local rowHeight, yOffset = C.RESERVES_ROW_HEIGHT, 0
        local seenSources = {}
        local firstRenderedRowBySource = {}
        local rowIndex = 0
        local headerIndex = 0

        for i = 1, #reservesDisplayList do
            local entry = reservesDisplayList[i]
            local source = entry.source

            if not seenSources[source] then
                seenSources[source] = true
                headerIndex = headerIndex + 1
                local header = module:CreateReserveHeader(scrollChild, source, yOffset, headerIndex)
                reserveHeaders[#reserveHeaders + 1] = header
                yOffset = yOffset + C.RESERVE_HEADER_HEIGHT
            end

            if not collapsedBossGroups[source] then
                rowIndex = rowIndex + 1
                local isFirstInGroup = not firstRenderedRowBySource[source]
                local row = module:CreateReserveRow(scrollChild, entry, yOffset, rowIndex, isFirstInGroup)
                firstRenderedRowBySource[source] = true
                reserveItemRows[#reserveItemRows + 1] = row
                yOffset = yOffset + rowHeight
            end
        end

        scrollChild:SetHeight(yOffset)
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end

    function module:CreateReserveHeader(parent, source, yOffset, index)
        local headerName = frameName .. "ReserveHeader" .. index
        local header = _G[headerName] or CreateFrame("Button", headerName, parent, "KRTReserveHeaderTemplate")
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        header._source = source
        if not header._initialized then
            header.label = _G[headerName .. "Label"]
            header:SetScript("OnClick", ReserveHeaderOnClick)
            header._initialized = true
        end
        if header.label then
            local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or
                "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
            header.label:SetText(prefix .. source)
        end
        header:Show()
        return header
    end

    local function SetupReserveIcon(row)
        if not row or not row.iconTexture or not row.iconBtn then return end
        row.iconTexture:ClearAllPoints()
        row.iconTexture:SetPoint("TOPLEFT", row.iconBtn, "TOPLEFT", 2, -2)
        row.iconTexture:SetPoint("BOTTOMRIGHT", row.iconBtn, "BOTTOMRIGHT", -2, 2)
        row.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTexture:SetDrawLayer("OVERLAY")
    end

    local function SetupReserveRowDecor(row)
        if not row or row._decorInitialized then return end
        local topSeparator = row:CreateTexture(nil, "BORDER")
        topSeparator:SetTexture("Interface\\Buttons\\WHITE8x8")
        topSeparator:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        topSeparator:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, 0)
        topSeparator:SetHeight(1)
        topSeparator:Hide()
        row.topSeparator = topSeparator

        local separator = row:CreateTexture(nil, "BORDER")
        separator:SetTexture("Interface\\Buttons\\WHITE8x8")
        separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
        separator:SetHeight(1)
        row.separator = separator
        row._decorInitialized = true
    end

    -- Create a new row for displaying a reserve
    function module:CreateReserveRow(parent, info, yOffset, index, isFirstInGroup)
        local rowName = frameName .. "ReserveRow" .. index
        local row = _G[rowName] or CreateFrame("Frame", rowName, parent, "KRTReserveRowTemplate")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        row._rawID = info.itemId
        if not row._initialized then
            row.background = _G[rowName .. "Background"]
            row.iconBtn = _G[rowName .. "IconBtn"]
            row.iconTexture = _G[rowName .. "IconBtnIconTexture"]
            row.textBlock = _G[rowName .. "TextBlock"]
            SetupReserveIcon(row)
            SetupReserveRowDecor(row)
            if row.textBlock and row.iconBtn then
                row.textBlock:SetFrameLevel(row.iconBtn:GetFrameLevel() + 1)
            end
            row.nameText = _G[rowName .. "TextBlockName"]
            row.sourceText = _G[rowName .. "TextBlockSource"]
            row.playerText = _G[rowName .. "TextBlockPlayers"]
            row.quantityText = _G[rowName .. "Quantity"]
            SetupReserveRowTooltip(row)
            if row.sourceText then
                row.sourceText:SetText("")
                row.sourceText:Hide()
            end
            row._initialized = true
        end
        ApplyReserveRowData(row, info, index, isFirstInGroup)
        row:Show()
        rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
        tinsert(rowsByItemID[info.itemId], row)

        return row
    end

    -- ----- SR Announcement Formatting ----- --

    -- Returns a list of formatted player tokens for an item.
    -- useColor:
    --   true/nil -> UI rendering (class colors)
    --   false    -> chat-safe rendering (no class color codes)
    -- showPlus:
    --   true/nil -> include "(P+N)" when Plus System is enabled
    --   false    -> hide Plus suffixes from formatted player tokens
    -- showMulti:
    --   true/nil -> include "(xN)" when Multi-reserve is enabled
    --   false    -> hide multi-reserve count suffixes from player tokens
    function module:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        if not itemId then return {} end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then return {} end

        -- Aggregate per player so we can apply sorting and reuse meta (class/plus).
        local data = { players = {}, playerCounts = {}, playerMeta = {} }
        for i = 1, #list do
            local r = list[i]
            if type(r) == "table" then
                AddReservePlayer(data, r)
            end
        end

        local tokens = BuildPlayerTokens(
            itemId,
            data.players,
            data.playerCounts,
            data.playerMeta,
            useColor,
            showPlus,
            showMulti
        )
        local out = {}
        for i = 1, #tokens do
            out[i] = tokens[i]
        end
        return out
    end

    -- Returns the formatted player list for an item (comma-separated).
    -- useColor, showPlus, and showMulti follow the same rules as GetPlayersForItem.
    function module:FormatReservedPlayersLine(itemId, useColor, showPlus, showMulti)
        addon:debug(Diag.D.LogReservesFormatPlayers:format(itemId))
        local list = self:GetPlayersForItem(itemId, useColor, showPlus, showMulti)
        -- Log the list of players found for the item
        addon:debug(Diag.D.LogReservesPlayersList:format(itemId, tconcat(list, ", ")))
        return #list > 0 and tconcat(list, ", ") or ""
    end
end
