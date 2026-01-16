local addonName, addon = ...
addon = addon or _G.KRT
local Utils = addon.Utils
local C = addon.C
local tinsert, tremove, tconcat, twipe = table.insert, table.remove, table.concat, table.wipe
local format, find, strlen = string.format, string.find, string.len
local strsub, gsub, lower, upper = string.sub, string.gsub, string.lower, string.upper

---============================================================================
-- Reserves Module
-- Manages item reserves, import, and display.
---============================================================================
do
    -------------------------------------------------------
    -- 1. Create/retrieve the module table
    -------------------------------------------------------
    addon.Reserves = addon.Reserves or {}
    local module = addon.Reserves
    local L = addon.L
    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON

    -------------------------------------------------------
    -- Internal state
    -------------------------------------------------------
    -- UI Elements
    local frameName
    local reserveListFrame, scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows, rowsByItemID = {}, {}

    -- State variables
    local localized = false
    local updateInterval = C.UPDATE_INTERVAL_RESERVES
    local reservesData = {}
    local reservesByItemID = {}
    local reservesDisplayList = {}
    local reservesDirty = false
    local pendingItemInfo = {}
    local pendingItemCount = 0
    local collapsedBossGroups = {}
    local grouped = {}

    -------------------------------------------------------
    -- Private helpers
    -------------------------------------------------------

    local playerTextTemp = {}

    local function MarkPendingItem(itemId, hasName, hasIcon)
        if not itemId then return nil end
        local pending = pendingItemInfo[itemId]
        if not pending then
            pending = {
                nameReady = false,
                iconReady = false
            }
            pendingItemInfo[itemId] = pending
            pendingItemCount = pendingItemCount + 1
            addon:debug("Reserves: track pending itemId=%d pending=%d.", itemId, pendingItemCount)
        end
        if hasName then
            pending.nameReady = true
        end
        if hasIcon then
            pending.iconReady = true
        end
        return pending
    end

    local function CompletePendingItem(itemId)
        if not itemId or not pendingItemInfo[itemId] then return end
        pendingItemInfo[itemId] = nil
        if pendingItemCount > 0 then
            pendingItemCount = pendingItemCount - 1
        end
        addon:debug("Reserves: item ready itemId=%d pending=%d.", itemId, pendingItemCount)
        if pendingItemCount == 0 then
            addon:debug("Reserves: pending item info complete.")
            if reserveListFrame and reserveListFrame:IsShown() then
                module:RefreshWindow()
            end
        end
    end

    local function FormatReservePlayerName(name, count)
        if count and count > 1 then
            return name .. format(L.StrReserveCountSuffix, count)
        end
        return name
    end

    local function AddReservePlayer(data, name, count)
        if not data.players then data.players = {} end
        if not data.playerCounts then data.playerCounts = {} end
        local existing = data.playerCounts[name]
        if existing then
            data.playerCounts[name] = existing + (count or 1)
        else
            data.players[#data.players + 1] = name
            data.playerCounts[name] = count or 1
        end
    end

    local function BuildPlayersText(players, counts)
        if not players then return "" end
        twipe(playerTextTemp)
        for i = 1, #players do
            local name = players[i]
            playerTextTemp[#playerTextTemp + 1] = FormatReservePlayerName(name, counts and counts[name] or 1)
        end
        return tconcat(playerTextTemp, ", ")
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
                    local source = r.source or "Unknown"
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
                        }
                        bySource[itemId] = data
                    end
                    AddReservePlayer(data, r.player or "?", r.quantity or 1)
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
                    twipe(target.players)
                    twipe(target.playerCounts)
                    for i = 1, #data.players do
                        local name = data.players[i]
                        target.players[i] = name
                        target.playerCounts[name] = data.playerCounts[name]
                    end
                    target.playersText = BuildPlayersText(target.players, target.playerCounts)
                    target.players = nil
                    target.playerCounts = nil
                    remaining[#remaining + 1] = target
                else
                    data.playersText = BuildPlayersText(data.players, data.playerCounts)
                    data.players = nil
                    data.playerCounts = nil
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
        reservesDirty = true
        for _, player in pairs(reservesData) do
            if type(player) == "table" and type(player.reserves) == "table" then
                local playerName = player.original or "?"
                for i = 1, #player.reserves do
                    local r = player.reserves[i]
                    if type(r) == "table" and r.rawID then
                        r.player = r.player or playerName
                        local list = reservesByItemID[r.rawID]
                        if not list then
                            list = {}
                            reservesByItemID[r.rawID] = list
                        end
                        list[#list + 1] = r
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
                        local source = r.source or "Unknown"

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
                            }
                            bySource[itemId] = data
                        end

                        AddReservePlayer(data, r.player or "?", r.quantity or 1)
                    end
                end
            end
        end

        for _, byItem in pairs(grouped) do
            for _, data in pairs(byItem) do
                data.playersText = BuildPlayersText(data.players, data.playerCounts)
                data.players = nil
                data.playerCounts = nil
                reservesDisplayList[#reservesDisplayList + 1] = data
            end
        end
    end

    local function SetupReserveRowTooltip(row)
        if not row or not row.iconBtn then return end
        row.iconBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
            if row._itemLink then
                GameTooltip:SetHyperlink(row._tooltipTitle)
            elseif row._tooltipTitle then
                GameTooltip:SetText(row._tooltipTitle, 1, 1, 1)
            end
            if row._tooltipSource then
                GameTooltip:AddLine(row._tooltipSource, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        row.iconBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function ApplyReserveRowData(row, info, index)
        if not row or not info then return end
        row._itemId = info.itemId
        row._itemLink = info.itemLink
        row._itemName = info.itemName
        row._source = info.source
        row._tooltipTitle = info.itemLink or info.itemName or ("Item ID: " .. (info.itemId or "?"))
        row._tooltipSource = info.source and ("Dropped by: " .. info.source) or nil

        if row.background then
            row.background:SetVertexColor(index % 2 == 0 and 0.1 or 0, 0.1, 0.1, 0.3)
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
            row.nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))
        end

        if row.playerText then
            row.playerText:SetText(info.playersText or "")
        end
        if row.quantityText then
            row.quantityText:Hide()
        end
    end

    local function ReserveHeaderOnClick(self)
        local source = self and self._source
        if not source then return end
        collapsedBossGroups[source] = not collapsedBossGroups[source]
        addon:debug("Reserves: toggle collapse source=%s state=%s.", source,
            tostring(collapsedBossGroups[source]))
        module:RefreshWindow()
    end

    -------------------------------------------------------
    -- Public methods
    -------------------------------------------------------

    -- Local functions
    local LocalizeUIFrame
    local UpdateUIFrame

    --------------------------------------------------------------------------
    -- Saved Data Management
    --------------------------------------------------------------------------

    function module:Save()
        RebuildIndex()
        addon:debug("Reserves: save entries=%d.", addon.tLength(reservesData))
        local saved = {}
        addon.tCopy(saved, reservesData)
        KRT_SavedReserves = saved
    end

    function module:Load()
        addon:debug("Reserves: load data=%s.", tostring(KRT_SavedReserves ~= nil))
        twipe(reservesData)
        if KRT_SavedReserves then
            addon.tCopy(reservesData, KRT_SavedReserves)
        end
        RebuildIndex()
    end

    function module:ResetSaved()
        addon:debug("Reserves: reset saved data.")
        KRT_SavedReserves = nil
        twipe(reservesData)
        twipe(reservesByItemID)
        twipe(reservesDisplayList)
        reservesDirty = true
        self:RefreshWindow()
        self:CloseWindow()
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

    --------------------------------------------------------------------------
    -- UI Window Management
    --------------------------------------------------------------------------

    function module:ShowWindow()
        if not reserveListFrame then
            addon:error("Reserve List frame not available.")
            return
        end
        addon:debug("Reserves: show list window.")
        reserveListFrame:Show()
        self:RefreshWindow()
    end

    function module:CloseWindow()
        addon:debug("Reserves: hide list window.")
        if reserveListFrame then reserveListFrame:Hide() end
    end

    function module:ShowImportBox()
        addon:debug("Reserves: open import window.")
        local frame = _G["KRTImportWindow"]
        if not frame then
            addon:error("KRTImportWindow not found.")
            return
        end
        frame:Show()
        Utils.resetEditBox(_G["KRTImportEditBox"])
        Utils.setFrameTitle(frame, L.StrImportReservesTitle)
    end

    function module:CloseImportWindow()
        local frame = _G["KRTImportWindow"]
        if frame then
            frame:Hide()
        end
    end

    function module:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        if not editBox then return end
        local csv = editBox:GetText()
        if csv and csv ~= "" then
            addon:info(L.LogSRImportRequested:format(#csv))
            self:ParseCSV(csv)
        end
        self:CloseImportWindow()
    end

    function module:OnLoad(frame)
        addon:debug("Reserves: frame loaded.")
        reserveListFrame = frame
        frameName = frame:GetName()

        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetScript("OnUpdate", UpdateUIFrame)

        scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
        scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

        local buttons = {
            CloseButton = "CloseWindow",
            ClearButton = "ResetSaved",
            QueryButton = "QueryMissingItems",
        }
        for suff, method in pairs(buttons) do
            local btn = _G["KRTReserveListFrame" .. suff]
            if btn and self[method] then
                btn:SetScript("OnClick", function() self[method](self) end)
                addon:debug("Reserves: bind button=%s action=%s.", suff, method)
            end
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug("Reserves: item info received itemId=%d.", itemId)
            if pendingItemInfo[itemId] then
                local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
                local icon = tex
                if type(icon) ~= "string" or icon == "" then
                    icon = GetItemIcon(itemId)
                end
                local hasName = type(name) == "string" and name ~= ""
                    and type(link) == "string" and link ~= ""
                local hasIcon = type(icon) == "string" and icon ~= ""
                if hasName then
                    addon:debug("Reserves: update item data %s.", link)
                    self:UpdateReserveItemData(itemId, name, link, icon)
                else
                    addon:debug("Reserves: item info missing itemId=%d.", itemId)
                end
                MarkPendingItem(itemId, hasName, hasIcon)
                if hasName and hasIcon then
                    addon:info(L.LogSRItemInfoResolved:format(itemId, tostring(link)))
                    CompletePendingItem(itemId)
                else
                    addon:debug("Reserves: item info still pending itemId=%d.", itemId)
                    self:QueryItemInfo(itemId)
                end
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Localization and UI Update
    --------------------------------------------------------------------------

    function LocalizeUIFrame()
        if localized then
            addon:debug("Reserves: UI already localized.")
            return
        end
        if frameName then
            Utils.setFrameTitle(frameName, L.StrRaidReserves)
            addon:debug("Reserves: UI localized %s.", L.StrRaidReserves)
        end
        localized = true
    end

    -- Update UI Frame:
    function UpdateUIFrame(self, elapsed)
        LocalizeUIFrame()
        Utils.throttledUIUpdate(self, frameName, updateInterval, elapsed, function()
            local hasData = module:HasData()
            local clearButton = _G[frameName .. "ClearButton"]
            if clearButton then
                Utils.enableDisable(clearButton, hasData)
            end
            local queryButton = _G[frameName .. "QueryButton"]
            if queryButton then
                Utils.enableDisable(queryButton, hasData)
            end
        end)
    end

    --------------------------------------------------------------------------
    -- Reserve Data Handling
    --------------------------------------------------------------------------

    function module:GetReserve(playerName)
        if type(playerName) ~= "string" then return nil end
        local player = Utils.normalizeLower(playerName)
        local reserve = reservesData[player]

        -- Log when the function is called and show the reserve for the player
        if reserve then
            addon:debug("Reserves: player found %s data=%s.", playerName, tostring(reserve))
        else
            addon:debug("Reserves: player not found %s.", playerName)
        end

        return reserve
    end

    -- Get all reserves:
    function module:GetAllReserves()
        addon:debug("Reserves: fetch all players=%d.", addon.tLength(reservesData))
        return reservesData
    end

    -- Parse imported text
    function module:ParseCSV(csv)
        if type(csv) ~= "string" or not csv:match("%S") then
            addon:error("Import failed: empty or invalid data.")
            return
        end

        addon:debug("Reserves: parse CSV start.")
        twipe(reservesData)
        twipe(reservesByItemID)
        reservesDirty = true

        local function cleanCSVField(field)
            if not field then return nil end
            return Utils.trimText(field:gsub('^"(.-)"$', '%1'), true)
        end

        local firstLine = true
        for line in csv:gmatch("[^\r\n]+") do
            if firstLine then
                firstLine = false
            else
                local _, itemIdStr, source, playerName, class, spec, note, plus = line:match(
                    '^"?(.-)"?,(.-),(.-),(.-),(.-),(.-),(.-),(.-)')

                itemIdStr = cleanCSVField(itemIdStr)
                source = cleanCSVField(source)
                playerName = cleanCSVField(playerName)
                class = cleanCSVField(class)
                spec = cleanCSVField(spec)
                note = cleanCSVField(note)
                plus = cleanCSVField(plus)

                local itemId = tonumber(itemIdStr)
                local normalized = Utils.normalizeLower(playerName, true)

                if normalized and itemId then
                    reservesData[normalized] = reservesData[normalized] or {
                        original = playerName,
                        reserves = {}
                    }

                    local list = reservesData[normalized].reserves
                    local found = false
                    for i = 1, #list do
                        local entry = list[i]
                        if entry and entry.rawID == itemId then
                            entry.quantity = (entry.quantity or 1) + 1
                            found = true
                            break
                        end
                    end

                    if not found then
                        list[#list + 1] = {
                            rawID = itemId,
                            itemLink = nil,
                            itemName = nil,
                            itemIcon = nil,
                            quantity = 1,
                            class = class ~= "" and class or nil,
                            spec = spec ~= "" and spec or nil,
                            note = note ~= "" and note or nil,
                            plus = tonumber(plus) or 0,
                            source = source ~= "" and source or nil,
                            player = playerName
                        }
                    end
                else
                    addon:warn(L.LogSRParseSkippedLine:format(tostring(line)))
                end
            end
        end

        RebuildIndex()
        addon:debug("Reserves: parse CSV complete players=%d.", addon.tLength(reservesData))
        addon:info(L.LogSRImportComplete:format(addon.tLength(reservesData)))
        self:RefreshWindow()
        self:Save()
    end

    --------------------------------------------------------------------------
    -- Item Info Querying
    --------------------------------------------------------------------------

    function module:QueryItemInfo(itemId)
        if not itemId then return end
        addon:debug("Reserves: query item info itemId=%d.", itemId)
        local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
        local icon = tex
        if type(icon) ~= "string" or icon == "" then
            icon = GetItemIcon(itemId)
        end
        local hasName = type(name) == "string" and name ~= ""
            and type(link) == "string" and link ~= ""
        local hasIcon = type(icon) == "string" and icon ~= ""
        if hasName then
            self:UpdateReserveItemData(itemId, name, link, icon)
        end
        MarkPendingItem(itemId, hasName, hasIcon)
        if hasName and hasIcon then
            addon:debug("Reserves: item info ready itemId=%d name=%s.", itemId, name)
            CompletePendingItem(itemId)
            return true
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
        addon:debug("Reserves: item info pending itemId=%d.", itemId)
        return false
    end

    -- Query all missing items for reserves
    function module:QueryMissingItems(silent)
        local seen = {}
        local count = 0
        local updated = false
        addon:debug("Reserves: query missing items.")
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
        if updated and reserveListFrame and reserveListFrame:IsShown() then
            self:RefreshWindow()
        end
        if not silent then
            if count > 0 then
                addon:info(L.MsgReserveItemsRequested, count)
            else
                addon:info(L.MsgReserveItemsReady)
            end
        end
        addon:debug("Reserves: missing items requested=%d.", count)
        addon:debug(L.LogSRQueryMissingItems:format(tostring(updated), count))
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
            row._tooltipTitle = itemLink or itemName or ("Item ID: " .. itemId)
            row._tooltipSource = row._source and ("Dropped by: " .. row._source) or nil
            if row.iconTexture then
                local resolvedIcon = icon
                if type(resolvedIcon) ~= "string" or resolvedIcon == "" then
                    resolvedIcon = fallbackIcon
                end
                row.iconTexture:SetTexture(resolvedIcon)
                row.iconTexture:Show()
            end
            if row.nameText then
                row.nameText:SetText(itemLink or itemName or ("Item ID: " .. itemId))
            end
        end
    end

    -- Get reserve count for a specific item for a player
    function module:GetReserveCountForItem(itemId, playerName)
        local normalized = Utils.normalizeLower(playerName, true)
        local entry = reservesData[normalized]
        if not entry then return 0 end
        addon:debug("Reserves: check count itemId=%d player=%s.", itemId, playerName)
        for _, r in ipairs(entry.reserves or {}) do
            if r.rawID == itemId then
                addon:debug("Reserves: found itemId=%d player=%s qty=%d.", itemId, playerName,
                    r.quantity)
                return r.quantity or 1
            end
        end
        addon:debug("Reserves: none itemId=%d player=%s.", itemId, playerName)
        return 0
    end

    --------------------------------------------------------------------------
    -- UI Display
    --------------------------------------------------------------------------

    function module:RefreshWindow()
        if not reserveListFrame or not scrollChild then return end

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
                local row = module:CreateReserveRow(scrollChild, entry, yOffset, rowIndex)
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

    -- Create a new row for displaying a reserve
    function module:CreateReserveRow(parent, info, yOffset, index)
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
        ApplyReserveRowData(row, info, index)
        row:Show()
        rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
        tinsert(rowsByItemID[info.itemId], row)

        return row
    end

    --------------------------------------------------------------------------
    -- SR Announcement Formatting
    --------------------------------------------------------------------------

    function module:GetPlayersForItem(itemId)
        if not itemId then return {} end
        local list = reservesByItemID[itemId]
        if type(list) ~= "table" then return {} end

        local players = {}
        for i = 1, #list do
            local r = list[i]
            local qty = (type(r) == "table" and r.quantity) or 1
            qty = qty or 1
            local name = (type(r) == "table" and r.player) or "?"
            players[#players + 1] = FormatReservePlayerName(name, qty)
        end
        return players
    end

    function module:FormatReservedPlayersLine(itemId)
        addon:debug("Reserves: format players itemId=%d.", itemId)
        local list = self:GetPlayersForItem(itemId)
        -- Log the list of players found for the item
        addon:debug("Reserves: players itemId=%d list=%s.", itemId, tconcat(list, ", "))
        return #list > 0 and tconcat(list, ", ") or ""
    end
end

