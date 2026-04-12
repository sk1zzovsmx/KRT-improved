-- ----- KRT Lua Contract ----- --
-- deps: local addon = select(2, ...)
-- shared: local feature = addon.Core.GetFeatureShared()
-- exports: publish module APIs on addon.*
-- events: document inbound/outbound events in module body
local addon = select(2, ...)
local feature = addon.Core.GetFeatureShared()

local L = feature.L
local Diag = feature.Diag

local Frames = feature.Frames or addon.Frames
local UIScaffold = addon.UIScaffold
local UIPrimitives = addon.UIPrimitives
local Events = feature.Events or addon.Events
local C = feature.C
local Options = feature.Options or addon.Options
local Bus = feature.Bus or addon.Bus

local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local pairs, type = pairs, type
local format = string.format
local tostring, tonumber = tostring, tonumber

local InternalEvents = Events.Internal
local UIFacade = addon.UI

do
    if not UIFacade:IsEnabled("Reserves") then
        return
    end

    addon.Widgets.ReservesUI = addon.Widgets.ReservesUI or {}
    local module = addon.Widgets.ReservesUI
    module._ui = UIScaffold.EnsureModuleUi(module)
    local UI = module._ui
    local Reserves = addon.Services and addon.Services.Reserves

    -- ----- Internal state ----- --

    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON
    local getFrame = makeModuleFrameGetter(module, "KRTReserveListFrame")
    local scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows = {}
    local rowsByItemID = {}
    local lastQueryAttemptAt = 0
    local reserveRowStyle = {
        odd = { 0.04, 0.06, 0.09, 0.30 },
        even = { 0.08, 0.10, 0.14, 0.36 },
        separator = { 1.0, 1.0, 1.0, 0.10 },
    }
    local queryCooldownSeconds = tonumber(C.RESERVES_QUERY_COOLDOWN_SECONDS) or 2

    -- ----- Private helpers ----- --

    function UI.AcquireRefs(frame)
        return {
            closeButton = Frames.Ref(frame, "CloseButton"),
            clearButton = Frames.Ref(frame, "ClearButton"),
            queryButton = Frames.Ref(frame, "QueryButton"),
            scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"],
            scrollChild = (frame.ScrollFrame and frame.ScrollFrame.ScrollChild) or _G["KRTReserveListFrameScrollChild"],
        }
    end

    local function clamp(v, lo, hi)
        if v < lo then
            return lo
        end
        if v > hi then
            return hi
        end
        return v
    end

    local function setupReserveRowTooltip(row)
        if not row then
            return
        end

        local function showItemTooltip(self)
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

        local function showPlayersTooltip(self)
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

        if row.iconBtn then
            row.iconBtn:SetScript("OnEnter", showItemTooltip)
            row.iconBtn:SetScript("OnLeave", Frames.HideTooltip)
        end

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
                hs:SetScript("OnEnter", showItemTooltip)
                hs:SetScript("OnLeave", Frames.HideTooltip)
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
                hs:SetScript("OnEnter", showPlayersTooltip)
                hs:SetScript("OnLeave", Frames.HideTooltip)
                row._playersHotspot = hs
            end
        end
    end

    local function updateReserveRowHotspots(row)
        if not row or not row.textBlock then
            return
        end
        local maxW = row.textBlock:GetWidth() or 0
        if maxW <= 0 then
            maxW = 200
        end
        local pad = 8

        if row._nameHotspot and row.nameText then
            local text = row.nameText:GetText() or ""
            if text ~= "" then
                local width = row.nameText.GetStringWidth and row.nameText:GetStringWidth() or 0
                row._nameHotspot:SetWidth(clamp(width + pad, 2, maxW))
                row._nameHotspot:EnableMouse(true)
            else
                row._nameHotspot:SetWidth(2)
                row._nameHotspot:EnableMouse(false)
            end
        end

        if row._playersHotspot and row.playerText then
            local text = row.playerText:GetText() or ""
            if text ~= "" then
                local width = row.playerText.GetStringWidth and row.playerText:GetStringWidth() or 0
                row._playersHotspot:SetWidth(clamp(width + pad, 2, maxW))
                row._playersHotspot:EnableMouse(true)
            else
                row._playersHotspot:SetWidth(2)
                row._playersHotspot:EnableMouse(false)
            end
        end
    end

    local function applyReserveRowData(row, info, index, isFirstInGroup)
        if not row or not info then
            return
        end
        local itemIdLabel = format(L.StrReservesItemIdLabel, tostring(info.itemId or "?"))
        local itemFallback = format(L.StrReservesItemFallback, tostring(info.itemId or "?"))
        local droppedBy = (info.source and info.source ~= "") and format(L.StrReservesTooltipDroppedBy, info.source) or nil

        row._itemId = info.itemId
        row._itemLink = info.itemLink
        row._itemName = info.itemName
        row._source = info.source
        row._tooltipTitle = info.itemLink or info.itemName or itemIdLabel
        row._tooltipSource = droppedBy
        row._playersTooltipLines = info.playersTooltipLines
        row._playersTextFull = info.playersTextFull or info.playersText

        local isEvenRow = (index % 2 == 0)
        if row.background then
            local bg = isEvenRow and reserveRowStyle.even or reserveRowStyle.odd
            row.background:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
        end
        if row.separator then
            local sepAlpha = isEvenRow and 0.1 or reserveRowStyle.separator[4]
            row.separator:SetVertexColor(reserveRowStyle.separator[1], reserveRowStyle.separator[2], reserveRowStyle.separator[3], sepAlpha)
            row.separator:Show()
        end
        if row.topSeparator then
            row.topSeparator:SetVertexColor(reserveRowStyle.separator[1], reserveRowStyle.separator[2], reserveRowStyle.separator[3], reserveRowStyle.separator[4])
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
            row.nameText:SetText(info.itemLink or info.itemName or itemFallback)
        end
        if row.playerText then
            row.playerText:SetText(info.playersText or "")
        end
        if row.quantityText then
            row.quantityText:Hide()
        end

        updateReserveRowHotspots(row)
    end

    local function reserveHeaderOnClick(self)
        local source = self and self._source
        if not source then
            return
        end
        if Reserves and Reserves.ToggleSourceCollapsed then
            Reserves:ToggleSourceCollapsed(source)
        end
        module:RequestRefresh()
    end

    function UI.Localize()
        if UI.Localized then
            addon:debug(Diag.D.LogReservesUIAlreadyLocalized)
            return
        end
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        if frameName then
            Frames.SetFrameTitle(frameName, L.StrRaidReserves)
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
        UI.Localized = true
    end

    function UI.Refresh()
        local frameName = UI.FrameName
        if not frameName then
            return
        end
        local hasData = Reserves and Reserves.HasData and Reserves:HasData() or false
        local clearButton = _G[frameName .. "ClearButton"]
        if clearButton then
            if hasData then
                clearButton:Show()
                UIPrimitives.EnableDisable(clearButton, true)
            else
                clearButton:Hide()
            end
        end
        local queryButton = _G[frameName .. "QueryButton"]
        if queryButton then
            UIPrimitives.EnableDisable(queryButton, hasData)
        end
    end

    local function setupReserveIcon(row)
        if not row or not row.iconTexture or not row.iconBtn then
            return
        end
        row.iconTexture:ClearAllPoints()
        row.iconTexture:SetPoint("TOPLEFT", row.iconBtn, "TOPLEFT", 2, -2)
        row.iconTexture:SetPoint("BOTTOMRIGHT", row.iconBtn, "BOTTOMRIGHT", -2, 2)
        row.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTexture:SetDrawLayer("OVERLAY")
    end

    local function setupReserveRowDecor(row)
        if not row or row._decorInitialized then
            return
        end

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

    -- ----- Public methods ----- --

    function module:CreateReserveHeader(parent, source, yOffset, index)
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
        local headerName = frameName .. "ReserveHeader" .. index
        local header = _G[headerName] or CreateFrame("Button", headerName, parent, "KRTReserveHeaderTemplate")
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        header._source = source
        if not header._initialized then
            header.label = _G[headerName .. "Label"]
            header:SetScript("OnClick", reserveHeaderOnClick)
            header._initialized = true
        end

        if header.label then
            local collapsed = Reserves and Reserves.IsSourceCollapsed and Reserves:IsSourceCollapsed(source)
            local prefix = collapsed and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
            header.label:SetText(prefix .. source)
        end

        header:Show()
        return header
    end

    function module:CreateReserveRow(parent, info, yOffset, index, isFirstInGroup)
        local frameName = UI.FrameName
        if not frameName then
            return nil
        end
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
            setupReserveIcon(row)
            setupReserveRowDecor(row)
            if row.textBlock and row.iconBtn then
                row.textBlock:SetFrameLevel(row.iconBtn:GetFrameLevel() + 1)
            end
            row.nameText = _G[rowName .. "TextBlockName"]
            row.sourceText = _G[rowName .. "TextBlockSource"]
            row.playerText = _G[rowName .. "TextBlockPlayers"]
            row.quantityText = _G[rowName .. "Quantity"]
            setupReserveRowTooltip(row)
            if row.sourceText then
                row.sourceText:SetText("")
                row.sourceText:Hide()
            end
            row._initialized = true
        end

        applyReserveRowData(row, info, index, isFirstInGroup)
        row:Show()
        rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
        tinsert(rowsByItemID[info.itemId], row)
        return row
    end

    local function renderReserveListUI()
        local frame = getFrame()
        if not frame or not scrollChild or not UI.FrameName then
            return
        end

        for i = 1, #reserveItemRows do
            reserveItemRows[i]:Hide()
        end
        twipe(reserveItemRows)
        twipe(rowsByItemID)

        for i = 1, #reserveHeaders do
            reserveHeaders[i]:Hide()
        end
        twipe(reserveHeaders)

        local rowHeight = C.RESERVES_ROW_HEIGHT
        local yOffset = 0
        local rowIndex = 0
        local headerIndex = 0
        local seenSources = {}
        local firstRenderedRowBySource = {}
        local displayList = Reserves and Reserves.GetDisplayList and Reserves:GetDisplayList() or {}

        for i = 1, #displayList do
            local entry = displayList[i]
            local source = entry.source

            if not seenSources[source] then
                seenSources[source] = true
                headerIndex = headerIndex + 1
                local header = module:CreateReserveHeader(scrollChild, source, yOffset, headerIndex)
                reserveHeaders[#reserveHeaders + 1] = header
                yOffset = yOffset + C.RESERVE_HEADER_HEIGHT
            end

            local collapsed = Reserves and Reserves.IsSourceCollapsed and Reserves:IsSourceCollapsed(source)
            if not collapsed then
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

    function module:PrimeItemInfoQuery(itemId)
        if not itemId then
            return
        end
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
    end

    function module:QueryItemInfo(itemId)
        if not (Reserves and Reserves.QueryItemInfo) then
            return false
        end
        return Reserves:QueryItemInfo(itemId)
    end

    function module:QueryMissingItems(silent)
        if not (Reserves and Reserves.QueryMissingItems) then
            return false, 0
        end

        local updated, count = Reserves:QueryMissingItems(silent, function(itemId)
            module:PrimeItemInfoQuery(itemId)
        end)

        if updated then
            module:RequestRefresh("query_missing_items")
        end

        return updated, count
    end

    local function shouldThrottleQueryMissingItems()
        local now = GetTime and GetTime() or nil
        if type(now) ~= "number" then
            return false
        end
        if (now - lastQueryAttemptAt) < queryCooldownSeconds then
            return true
        end
        lastQueryAttemptAt = now
        return false
    end

    local function resetSavedFromUI()
        local out
        if Reserves and Reserves.ResetSaved then
            out = Reserves:ResetSaved()
        end
        module:Hide()
        module:RequestRefresh("reset_saved")
        return out
    end

    function module:RefreshUI()
        if not UI.Localized then
            UI.Localize()
        end
        UI.Refresh()
        renderReserveListUI()
    end

    function module:Refresh()
        return self:RefreshUI()
    end

    local function BindHandlers(_, _, refs)
        scrollFrame = refs.scrollFrame or scrollFrame
        scrollChild = refs.scrollChild or scrollChild

        if refs.closeButton then
            refs.closeButton:SetScript("OnClick", function()
                module:Hide()
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("CloseButton", "Hide"))
        end

        if refs.clearButton then
            refs.clearButton:SetScript("OnClick", function()
                resetSavedFromUI()
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("ClearButton", "ResetSaved"))
        end

        if refs.queryButton then
            refs.queryButton:SetScript("OnClick", function()
                if shouldThrottleQueryMissingItems() then
                    addon:info(L.MsgReserveItemsQueryCooldown, queryCooldownSeconds)
                    return
                end
                module:QueryMissingItems(false)
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("QueryButton", "QueryMissingItems"))
        end
    end

    function module:OnLoad(frame)
        addon:debug(Diag.D.LogReservesFrameLoaded)
        UI.FrameName = Frames.InitModuleFrame(module, frame, {
            enableDrag = true,
            hookOnShow = function()
                addon:debug(Diag.D.LogReservesShowWindow)
            end,
            hookOnHide = function()
                addon:debug(Diag.D.LogReservesHideWindow)
            end,
        }) or UI.FrameName
        UI.Loaded = UI.FrameName ~= nil
        if not UI.Loaded then
            return
        end

        scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"]
        scrollChild = scrollFrame and scrollFrame.ScrollChild or _G["KRTReserveListFrameScrollChild"]

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug(Diag.D.LogReservesItemInfoReceived:format(itemId))
            if not (Reserves and Reserves._HasPendingItem and Reserves._HasPendingItem(itemId)) then
                return
            end

            local resolved = module:QueryItemInfo(itemId)
            if not resolved then
                module:PrimeItemInfoQuery(itemId)
            end
        end)
    end

    local function OnLoadFrame(frame)
        module:OnLoad(frame)
        return UI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = module,
        getFrame = getFrame,
        acquireRefs = UI.AcquireRefs,
        bind = BindHandlers,
        localize = function()
            UI.Localize()
        end,
        onLoad = OnLoadFrame,
    })

    -- ----- Import widget controller ----- --

    module.Import = module.Import or {}
    local Import = module.Import
    Import._ui = Import._ui
        or {
            Loaded = false,
            Bound = false,
            Localized = false,
            Dirty = true,
            Reason = nil,
            FrameName = nil,
        }
    local ImportUI = Import._ui
    local getImportFrame = makeModuleFrameGetter(Import, "KRTImportWindow")
    local MODE_MULTI, MODE_PLUS = 0, 1

    function ImportUI.AcquireRefs(frame)
        return {
            cancelButton = _G["KRTImportCancelButton"],
            confirmButton = _G["KRTImportConfirmButton"],
            editBox = _G["KRTImportEditBox"],
            modeSlider = _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"],
            status = _G["KRTImportWindowStatus"],
            frame = frame,
        }
    end

    local function getImportModeString()
        if Reserves and Reserves.GetImportMode then
            return Reserves:GetImportMode()
        end
        local value = addon.options and addon.options.srImportMode
        if value == MODE_PLUS then
            return "plus"
        end
        return "multi"
    end

    local function getImportModeValue()
        return (getImportModeString() == "plus") and MODE_PLUS or MODE_MULTI
    end

    local function getModeSlider()
        return _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"]
    end

    local function setImportStatus(text, r, g, b)
        local status = _G["KRTImportWindowStatus"]
        if not status then
            return
        end
        status:SetText(text or "")
        if r and g and b then
            status:SetTextColor(r, g, b)
        end
    end

    local function showReservesListAfterImport()
        Import:Hide()
        local reserveFrame = getFrame()
        if not (reserveFrame and reserveFrame.IsShown and reserveFrame:IsShown()) then
            module:Toggle()
        else
            module:RequestRefresh()
        end
    end

    local function ensureWrongCSVPopup()
        if not StaticPopupDialogs then
            return
        end
        if StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] then
            return
        end

        StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] = {
            text = L.ErrCSVWrongForPlus,
            button1 = L.BtnSwitchToMulti,
            button2 = L.BtnCancel,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnShow = function(self, data)
                if not self or not self.text then
                    return
                end
                local text = L.ErrCSVWrongForPlus
                if type(data) == "table" and data.player then
                    text = L.ErrCSVWrongForPlusWithPlayer:format(tostring(data.player))
                end
                self.text:SetText(text)
            end,
            OnAccept = function(_, data)
                if type(data) ~= "table" or type(data.csv) ~= "string" then
                    return
                end
                Import:SetImportMode(MODE_MULTI)
                local parsed = Reserves and Reserves.ParseImport and Reserves:ParseImport(data.csv, "multi")
                if not parsed then
                    setImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
                    return
                end

                local ok, nPlayers = Reserves:ApplyImport(parsed, nil, { reason = "import" })
                if not ok then
                    setImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
                    return
                end

                setImportStatus(format(L.SuccessReservesParsed, tostring(nPlayers)), 0.2, 1, 0.2)
                showReservesListAfterImport()
            end,
        }
    end

    function ImportUI.Localize()
        if ImportUI.Localized then
            return
        end
        local frame = getImportFrame()
        if not frame then
            addon:error(Diag.E.LogReservesImportWindowMissing)
            return
        end

        Frames.SetFrameTitle(ImportUI.FrameName or frame, L.StrImportReservesTitle)

        local hint = _G["KRTImportWindowHint"]
        if hint then
            hint:SetText(L.StrImportReservesHint)
        end

        local confirmButton = _G["KRTImportConfirmButton"]
        if confirmButton then
            confirmButton:SetText(L.BtnImport)
        end

        local cancelButton = _G["KRTImportCancelButton"]
        if cancelButton then
            cancelButton:SetText(L.BtnClose)
        end

        ImportUI.Localized = true
    end

    local function bindImportHandlers(_, _, refs)
        Frames.SafeSetScript(refs.cancelButton, "OnClick", function()
            Import:Hide()
        end)
        Frames.SafeSetScript(refs.confirmButton, "OnClick", function()
            Import:ImportFromEditBox()
        end)
        Frames.SafeSetScript(refs.editBox, "OnEscapePressed", function()
            Import:Hide()
        end)
        Frames.SafeSetScript(refs.modeSlider, "OnValueChanged", function(self, value)
            Import:OnModeSliderChanged(self, value)
        end)
        Import:OnModeSliderLoad(refs.modeSlider)
    end

    function Import:SetImportMode(modeValue, suppressSlider)
        local mode = (modeValue == MODE_PLUS) and "plus" or "multi"
        if Reserves and Reserves.SetImportMode then
            Reserves:SetImportMode(mode, true)
        else
            Options.SetOption("srImportMode", (mode == "plus") and MODE_PLUS or MODE_MULTI)
        end

        if suppressSlider then
            return
        end

        local slider = getModeSlider()
        if slider and slider.SetValue then
            slider:SetValue(getImportModeValue())
        end
    end

    function Import:OnModeSliderLoad(slider)
        if not slider then
            return
        end
        slider:SetMinMaxValues(MODE_MULTI, MODE_PLUS)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then
            slider:SetObeyStepOnDrag(true)
        end

        local low = _G[slider:GetName() .. "Low"]
        local high = _G[slider:GetName() .. "High"]
        local text = _G[slider:GetName() .. "Text"]
        if low then
            low:SetText(L.StrImportModeMulti or "Multi-reserve")
        end
        if high then
            high:SetText(L.StrImportModePlus or "Plus System")
        end
        if text then
            text:SetText(L.StrImportModeLabel or "")
        end

        slider:SetValue(getImportModeValue())
    end

    function Import:OnModeSliderChanged(slider, value)
        if not slider then
            return
        end
        local modeValue = tonumber(value) or MODE_MULTI
        if modeValue >= 0.5 then
            modeValue = MODE_PLUS
        else
            modeValue = MODE_MULTI
        end
        self:SetImportMode(modeValue, true)
    end

    function Import:RefreshUI()
        if not ImportUI.Localized then
            ImportUI.Localize()
        end

        local slider = getModeSlider()
        if slider and slider.SetValue then
            slider:SetValue(getImportModeValue())
        end

        local status = _G["KRTImportWindowStatus"]
        if status and (status:GetText() == nil or status:GetText() == "") then
            status:SetText("")
        end
    end

    function Import:Refresh()
        return self:RefreshUI()
    end

    function Import:OnLoad(frame)
        ImportUI.FrameName = Frames.InitModuleFrame(Import, frame, {
            enableDrag = true,
            hookOnShow = function()
                Frames.ResetEditBox(_G["KRTImportEditBox"])
                local editBox = _G["KRTImportEditBox"]
                if editBox then
                    editBox:SetFocus()
                    editBox:HighlightText()
                end
                setImportStatus("")
                Import:RequestRefresh()
            end,
        }) or ImportUI.FrameName
        ImportUI.Loaded = ImportUI.FrameName ~= nil
        if not ImportUI.Loaded then
            return
        end

        Import:RequestRefresh()
    end

    local function onLoadImportFrame(frame)
        Import:OnLoad(frame)
        return ImportUI.FrameName
    end

    UIScaffold.DefineModuleUi({
        module = Import,
        getFrame = getImportFrame,
        acquireRefs = ImportUI.AcquireRefs,
        bind = bindImportHandlers,
        localize = function()
            ImportUI.Localize()
        end,
        onLoad = onLoadImportFrame,
    })

    function Import:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        setImportStatus("")
        if not editBox then
            addon:error(Diag.E.LogReservesImportWindowMissing)
            return false, 0
        end

        local csv = editBox:GetText()
        if type(csv) ~= "string" or not csv:match("%S") then
            setImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0, "EMPTY"
        end

        addon:debug(Diag.D.LogSRImportRequested:format(#csv))
        ensureWrongCSVPopup()

        local mode = getImportModeString()
        local parsed, errCode, errData = Reserves:ParseImport(csv, mode, { source = "import_window" })
        if not parsed then
            if errCode == "CSV_WRONG_FOR_PLUS" then
                setImportStatus(L.ErrCSVWrongForPlusShort, 1, 0.2, 0.2)
                local popupData = { csv = csv }
                if type(errData) == "table" then
                    for key, value in pairs(errData) do
                        popupData[key] = value
                    end
                end
                StaticPopup_Show("KRT_WRONG_CSV_FOR_PLUS", nil, nil, popupData)
                return false, 0, errCode, errData
            end

            local errorText = (errCode == "NO_ROWS") and L.WarnNoValidRows or L.ErrImportReservesEmpty
            setImportStatus(errorText, 1, 0.2, 0.2)
            return false, 0, errCode, errData
        end

        local ok, nPlayersOrErr, applyErrData = Reserves:ApplyImport(parsed, nil, { reason = "import" })
        if not ok then
            setImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
            return false, 0, nPlayersOrErr, applyErrData
        end

        setImportStatus(format(L.SuccessReservesParsed, tostring(nPlayersOrErr)), 0.2, 1, 0.2)
        showReservesListAfterImport()
        return true, nPlayersOrErr
    end

    if UIFacade and UIFacade.Register then
        UIFacade:Register(
            "Reserves",
            UIScaffold.MakeStandardWidgetApi(module, {
                ToggleImport = function()
                    Import:Toggle()
                end,
                HideImport = function()
                    Import:Hide()
                end,
            })
        )
    end

    Bus.RegisterCallback(InternalEvents.ReservesDataChanged, function()
        module:RequestRefresh()
    end)
end
