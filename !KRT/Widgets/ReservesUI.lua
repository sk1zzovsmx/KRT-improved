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
local Events = feature.Events or addon.Events or {}
local C = feature.C
local Options = feature.Options or addon.Options
local Bus = feature.Bus or addon.Bus

local bindModuleRequestRefresh = feature.BindModuleRequestRefresh
local bindModuleToggleHide = feature.BindModuleToggleHide
local makeModuleFrameGetter = feature.MakeModuleFrameGetter

local _G = _G
local tinsert, twipe = table.insert, table.wipe
local pairs, type = pairs, type
local format = string.format
local tostring, tonumber = tostring, tonumber

local InternalEvents = Events.Internal
local UIFacade = addon.UI

local function isWidgetEnabled(widgetId)
    if UIFacade and type(UIFacade.IsEnabled) == "function" then
        return UIFacade:IsEnabled(widgetId)
    end
    return true
end

do
    if not isWidgetEnabled("Reserves") then
        return
    end

    addon.Widgets = addon.Widgets or {}
    addon.Widgets.ReservesUI = addon.Widgets.ReservesUI or addon.ReservesUI or {}
    addon.ReservesUI = addon.Widgets.ReservesUI -- Legacy alias during namespacing migration.
    local module = addon.Widgets.ReservesUI
    local Service = addon.Services and addon.Services.Reserves and addon.Services.Reserves.Service

    -- ----- Internal state ----- --

    local fallbackIcon = C.RESERVES_ITEM_FALLBACK_ICON
    local frameName
    local getFrame = Frames.MakeFrameGetter("KRTReserveListFrame")
    local scrollFrame, scrollChild
    local reserveHeaders = {}
    local reserveItemRows = {}
    local rowsByItemID = {}
    local localized = false
    local uiBound = false
    local scaffoldToggle, scaffoldHide
    local reserveRowStyle = {
        odd = { 0.04, 0.06, 0.09, 0.30 },
        even = { 0.08, 0.10, 0.14, 0.36 },
        separator = { 1.0, 1.0, 1.0, 0.10 },
    }

    UIScaffold.BootstrapModuleUi(module, getFrame, function()
        module:RequestRefresh()
    end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    scaffoldToggle = module.Toggle
    scaffoldHide = module.Hide

    -- ----- Private helpers ----- --

    local function AcquireRefs(frame)
        return {
            closeButton = Frames.Ref(frame, "CloseButton"),
            clearButton = Frames.Ref(frame, "ClearButton"),
            queryButton = Frames.Ref(frame, "QueryButton"),
            scrollFrame = frame.ScrollFrame or _G["KRTReserveListFrameScrollFrame"],
            scrollChild = (frame.ScrollFrame and frame.ScrollFrame.ScrollChild) or _G["KRTReserveListFrameScrollChild"],
        }
    end

    local function getReservesModule()
        local services = addon.Services
        return services and services.Reserves or nil
    end

    local function formatReserveItemIdLabel(itemId)
        local reserves = getReservesModule()
        if reserves and reserves.FormatReserveItemIdLabel then
            return reserves:FormatReserveItemIdLabel(itemId)
        end
        if Service and Service.FormatReserveItemIdLabel then
            return Service:FormatReserveItemIdLabel(itemId)
        end
        return format(L.StrReservesItemIdLabel, tostring(itemId or "?"))
    end

    local function formatReserveItemFallback(itemId)
        local reserves = getReservesModule()
        if reserves and reserves.FormatReserveItemFallback then
            return reserves:FormatReserveItemFallback(itemId)
        end
        if Service and Service.FormatReserveItemFallback then
            return Service:FormatReserveItemFallback(itemId)
        end
        return format(L.StrReservesItemFallback, tostring(itemId or "?"))
    end

    local function formatReserveDroppedBy(source)
        local reserves = getReservesModule()
        if reserves and reserves.FormatReserveDroppedBy then
            return reserves:FormatReserveDroppedBy(source)
        end
        if Service and Service.FormatReserveDroppedBy then
            return Service:FormatReserveDroppedBy(source)
        end
        if not source or source == "" then
            return nil
        end
        return format(L.StrReservesTooltipDroppedBy, source)
    end

    local function Clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    local function HideTooltip()
        GameTooltip:Hide()
    end

    local function SetupReserveRowTooltip(row)
        if not row then return end

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

        if row.iconBtn then
            row.iconBtn:SetScript("OnEnter", ShowItemTooltip)
            row.iconBtn:SetScript("OnLeave", HideTooltip)
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

    local function UpdateReserveRowHotspots(row)
        if not row or not row.textBlock then return end
        local maxW = row.textBlock:GetWidth() or 0
        if maxW <= 0 then maxW = 200 end
        local pad = 8

        if row._nameHotspot and row.nameText then
            local text = row.nameText:GetText() or ""
            if text ~= "" then
                local width = row.nameText.GetStringWidth and row.nameText:GetStringWidth() or 0
                row._nameHotspot:SetWidth(Clamp(width + pad, 2, maxW))
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
                row._playersHotspot:SetWidth(Clamp(width + pad, 2, maxW))
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
        row._tooltipTitle = info.itemLink or info.itemName or formatReserveItemIdLabel(info.itemId)
        row._tooltipSource = formatReserveDroppedBy(info.source)
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
            row.nameText:SetText(info.itemLink or info.itemName or formatReserveItemFallback(info.itemId))
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
        if Service and Service.ToggleSourceCollapsed then
            Service:ToggleSourceCollapsed(source)
        end
        module:RequestRefresh()
    end

    local function LocalizeUIFrame()
        if localized then
            addon:debug(Diag.D.LogReservesUIAlreadyLocalized)
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
        localized = true
    end

    local function UpdateUIFrame()
        LocalizeUIFrame()
        local hasData = Service and Service.HasData and Service:HasData() or false
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

    -- ----- Public methods ----- --

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
            local collapsed = Service and Service.IsSourceCollapsed and Service:IsSourceCollapsed(source)
            local prefix = collapsed and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or
                "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
            header.label:SetText(prefix .. source)
        end

        header:Show()
        return header
    end

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

    local function RenderReserveListUI()
        local frame = getFrame()
        if not frame or not scrollChild then return end

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
        local displayList = Service and Service.GetDisplayList and Service:GetDisplayList() or {}

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

            local collapsed = Service and Service.IsSourceCollapsed and Service:IsSourceCollapsed(source)
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
        if not itemId then return end
        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Hide()
    end

    function module:QueryItemInfo(itemId)
        if not (Service and Service.QueryItemInfo) then
            return false
        end
        return Service:QueryItemInfo(itemId)
    end

    function module:QueryMissingItems(silent)
        if not (Service and Service.QueryMissingItems) then
            return false, 0
        end

        local updated, count = Service:QueryMissingItems(silent, function(itemId)
            module:PrimeItemInfoQuery(itemId)
        end)

        if updated then
            module:RequestRefresh()
        end

        return updated, count
    end

    local function ResetSavedFromUI()
        local out
        if Service and Service.ResetSaved then
            out = Service:ResetSaved()
        end
        if module.Hide then
            module:Hide()
        end
        if module.RequestRefresh then
            module:RequestRefresh()
        end
        return out
    end

    function module:Refresh()
        UpdateUIFrame()
        RenderReserveListUI()
    end

    function module:BindUI()
        if uiBound and self.frame and self.refs then
            return self.frame, self.refs
        end

        local frame = getFrame()
        if not frame then
            return nil
        end
        if not frameName then
            self:OnLoad(frame)
        end

        local refs = AcquireRefs(frame)
        self.frame = frame
        self.refs = refs
        scrollFrame = refs.scrollFrame or scrollFrame
        scrollChild = refs.scrollChild or scrollChild

        uiBound = true
        return frame, refs
    end

    function module:EnsureUI()
        if uiBound and self.frame and self.refs then
            return self.frame
        end
        return self:BindUI()
    end

    function module:Toggle()
        if not self:EnsureUI() then
            return
        end
        if scaffoldToggle then
            return scaffoldToggle(self)
        end
    end

    function module:Hide()
        if not self:EnsureUI() then
            return
        end
        if scaffoldHide then
            return scaffoldHide(self)
        end
    end

    function module:OnLoad(frame)
        addon:debug(Diag.D.LogReservesFrameLoaded)
        frameName = Frames.InitModuleFrame(module, frame, {
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

        local closeButton = _G["KRTReserveListFrameCloseButton"]
        if closeButton then
            closeButton:SetScript("OnClick", function()
                if module.Hide then
                    module:Hide()
                end
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("CloseButton", "Hide"))
        end

        local clearButton = _G["KRTReserveListFrameClearButton"]
        if clearButton then
            clearButton:SetScript("OnClick", function()
                ResetSavedFromUI()
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("ClearButton", "ResetSaved"))
        end

        local queryButton = _G["KRTReserveListFrameQueryButton"]
        if queryButton then
            queryButton:SetScript("OnClick", function()
                module:QueryMissingItems(false)
            end)
            addon:debug(Diag.D.LogReservesBindButton:format("QueryButton", "QueryMissingItems"))
        end

        LocalizeUIFrame()

        local refreshFrame = CreateFrame("Frame")
        refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        refreshFrame:SetScript("OnEvent", function(_, _, itemId)
            addon:debug(Diag.D.LogReservesItemInfoReceived:format(itemId))
            if not (Service and Service.HasPendingItem and Service:HasPendingItem(itemId)) then
                return
            end

            local resolved = module:QueryItemInfo(itemId)
            if resolved then
                module:RequestRefresh()
            else
                module:PrimeItemInfoQuery(itemId)
            end
        end)
    end

    -- ----- Import widget controller ----- --

    module.Import = module.Import or {}
    local Import = module.Import
    local getImportFrame = makeModuleFrameGetter(Import, "KRTImportWindow")
    local importLocalized = false
    local importUiBound = false
    local importFrameName
    local importScaffoldToggle, importScaffoldHide
    local MODE_MULTI, MODE_PLUS = 0, 1

    UIScaffold.BootstrapModuleUi(Import, getImportFrame, function()
        if Import.RequestRefresh then
            Import:RequestRefresh()
        end
    end, {
        bindToggleHide = bindModuleToggleHide,
        bindRequestRefresh = bindModuleRequestRefresh,
    })

    importScaffoldToggle = Import.Toggle
    importScaffoldHide = Import.Hide

    local function AcquireImportRefs(frame)
        return {
            cancelButton = _G["KRTImportCancelButton"],
            confirmButton = _G["KRTImportConfirmButton"],
            editBox = _G["KRTImportEditBox"],
            modeSlider = _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"],
            status = _G["KRTImportWindowStatus"],
            frame = frame,
        }
    end

    local function GetImportModeString()
        if Service and Service.GetImportMode then
            return Service:GetImportMode()
        end
        local value = addon.options and addon.options.srImportMode
        if value == MODE_PLUS then return "plus" end
        return "multi"
    end

    local function GetImportModeValue()
        return (GetImportModeString() == "plus") and MODE_PLUS or MODE_MULTI
    end

    local function GetModeSlider()
        return _G["KRTImportWindowModeSlider"] or _G["KRTImportModeSlider"]
    end

    local function SetImportStatus(text, r, g, b)
        local status = _G["KRTImportWindowStatus"]
        if not status then return end
        status:SetText(text or "")
        if r and g and b then
            status:SetTextColor(r, g, b)
        end
    end

    local function ShowReservesListAfterImport()
        if Import.Hide then
            Import:Hide()
        end
        local reserveFrame = getFrame()
        if not (reserveFrame and reserveFrame.IsShown and reserveFrame:IsShown()) then
            if module.Toggle then
                module:Toggle()
            end
        else
            module:RequestRefresh()
        end
    end

    local function EnsureWrongCSVPopup()
        if not StaticPopupDialogs then return end
        if StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] then return end

        StaticPopupDialogs["KRT_WRONG_CSV_FOR_PLUS"] = {
            text = L.ErrCSVWrongForPlus,
            button1 = L.BtnSwitchToMulti,
            button2 = L.BtnCancel,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnShow = function(self, data)
                if not self or not self.text then return end
                local text = L.ErrCSVWrongForPlus
                if type(data) == "table" and data.player then
                    text = L.ErrCSVWrongForPlusWithPlayer:format(tostring(data.player))
                end
                self.text:SetText(text)
            end,
            OnAccept = function(_, data)
                if type(data) ~= "table" or type(data.csv) ~= "string" then return end
                Import:SetImportMode(MODE_MULTI)
                local parsed = Service and Service.ParseImport and Service:ParseImport(data.csv, "multi")
                if not parsed then
                    SetImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
                    return
                end

                local ok, nPlayers = Service:ApplyImport(parsed, nil, { reason = "import" })
                if not ok then
                    SetImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
                    return
                end

                SetImportStatus(format(L.SuccessReservesParsed, tostring(nPlayers)), 0.2, 1, 0.2)
                ShowReservesListAfterImport()
            end,
        }
    end

    local function LocalizeImportFrame()
        if importLocalized then return end
        local frame = getImportFrame()
        if not frame then
            addon:error(Diag.E.LogReservesImportWindowMissing)
            return
        end

        Frames.SetFrameTitle(frame, L.StrImportReservesTitle)

        local hint = _G["KRTImportWindowHint"]
        if hint then hint:SetText(L.StrImportReservesHint) end

        local confirmButton = _G["KRTImportConfirmButton"]
        if confirmButton then confirmButton:SetText(L.BtnImport) end

        local cancelButton = _G["KRTImportCancelButton"]
        if cancelButton then cancelButton:SetText(L.BtnClose) end

        importLocalized = true
    end

    function Import:BindUI()
        if importUiBound and self.frame and self.refs then
            return self.frame, self.refs
        end

        local frame = getImportFrame()
        if not frame then
            return nil
        end
        if not importFrameName then
            self:OnLoad(frame)
        end

        local refs = AcquireImportRefs(frame)
        self.frame = frame
        self.refs = refs

        Frames.SafeSetScript(refs.cancelButton, "OnClick", function()
            if Import.Hide then
                Import:Hide()
            end
        end)
        Frames.SafeSetScript(refs.confirmButton, "OnClick", function()
            Import:ImportFromEditBox()
        end)
        Frames.SafeSetScript(refs.editBox, "OnEscapePressed", function()
            if Import.Hide then
                Import:Hide()
            end
        end)
        Frames.SafeSetScript(refs.modeSlider, "OnValueChanged", function(self, value)
            Import:OnModeSliderChanged(self, value)
        end)
        Import:OnModeSliderLoad(refs.modeSlider)

        importUiBound = true
        return frame, refs
    end

    function Import:EnsureUI()
        if importUiBound and self.frame and self.refs then
            return self.frame
        end
        return self:BindUI()
    end

    function Import:Toggle()
        if not self:EnsureUI() then
            return
        end
        if importScaffoldToggle then
            return importScaffoldToggle(self)
        end
    end

    function Import:Hide()
        if not self:EnsureUI() then
            return
        end
        if importScaffoldHide then
            return importScaffoldHide(self)
        end
    end

    function Import:SetImportMode(modeValue, suppressSlider)
        local mode = (modeValue == MODE_PLUS) and "plus" or "multi"
        if Service and Service.SetImportMode then
            Service:SetImportMode(mode, true)
        else
            Options.SetOption("srImportMode", (mode == "plus") and MODE_PLUS or MODE_MULTI)
        end

        if suppressSlider then return end

        local slider = GetModeSlider()
        if slider and slider.SetValue then
            slider:SetValue(GetImportModeValue())
        end
    end

    function Import:OnModeSliderLoad(slider)
        if not slider then return end
        slider:SetMinMaxValues(MODE_MULTI, MODE_PLUS)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then
            slider:SetObeyStepOnDrag(true)
        end

        local low = _G[slider:GetName() .. "Low"]
        local high = _G[slider:GetName() .. "High"]
        local text = _G[slider:GetName() .. "Text"]
        if low then low:SetText(L.StrImportModeMulti or "Multi-reserve") end
        if high then high:SetText(L.StrImportModePlus or "Plus System") end
        if text then text:SetText(L.StrImportModeLabel or "") end

        slider:SetValue(GetImportModeValue())
    end

    function Import:OnModeSliderChanged(slider, value)
        if not slider then return end
        local modeValue = tonumber(value) or MODE_MULTI
        if modeValue >= 0.5 then
            modeValue = MODE_PLUS
        else
            modeValue = MODE_MULTI
        end
        self:SetImportMode(modeValue, true)
    end

    function Import:Refresh()
        LocalizeImportFrame()

        local slider = GetModeSlider()
        if slider and slider.SetValue then
            slider:SetValue(GetImportModeValue())
        end

        local status = _G["KRTImportWindowStatus"]
        if status and (status:GetText() == nil or status:GetText() == "") then
            status:SetText("")
        end
    end

    function Import:OnLoad(frame)
        importFrameName = Frames.InitModuleFrame(Import, frame, {
            enableDrag = true,
            hookOnShow = function()
                Frames.ResetEditBox(_G["KRTImportEditBox"])
                local editBox = _G["KRTImportEditBox"]
                if editBox then
                    editBox:SetFocus()
                    editBox:HighlightText()
                end
                SetImportStatus("")
                if Import.RequestRefresh then
                    Import:RequestRefresh()
                end
            end,
        })
        if not importFrameName then return end

        if Import.RequestRefresh then
            Import:RequestRefresh()
        end
    end

    function Import:ImportFromEditBox()
        local editBox = _G["KRTImportEditBox"]
        SetImportStatus("")
        if not editBox then
            addon:error(Diag.E.LogReservesImportWindowMissing)
            return false, 0
        end

        local csv = editBox:GetText()
        if type(csv) ~= "string" or not csv:match("%S") then
            SetImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
            addon:warn(Diag.W.LogReservesImportFailedEmpty)
            return false, 0, "EMPTY"
        end

        addon:debug(Diag.D.LogSRImportRequested:format(#csv))
        EnsureWrongCSVPopup()

        local mode = GetImportModeString()
        local parsed, errCode, errData = Service:ParseImport(csv, mode, { source = "import_window" })
        if not parsed then
            if errCode == "CSV_WRONG_FOR_PLUS" then
                SetImportStatus(L.ErrCSVWrongForPlusShort, 1, 0.2, 0.2)
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
            SetImportStatus(errorText, 1, 0.2, 0.2)
            return false, 0, errCode, errData
        end

        local ok, nPlayersOrErr, applyErrData = Service:ApplyImport(parsed, nil, { reason = "import" })
        if not ok then
            SetImportStatus(L.ErrImportReservesEmpty, 1, 0.2, 0.2)
            return false, 0, nPlayersOrErr, applyErrData
        end

        SetImportStatus(format(L.SuccessReservesParsed, tostring(nPlayersOrErr)), 0.2, 1, 0.2)
        ShowReservesListAfterImport()
        return true, nPlayersOrErr
    end

    if addon.UI and addon.UI.Register then
        addon.UI:Register("Reserves", {
            Toggle = function()
                if module.Toggle then
                    module:Toggle()
                end
            end,
            Hide = function()
                if module.Hide then
                    module:Hide()
                end
            end,
            RequestRefresh = function()
                if module.RequestRefresh then
                    module:RequestRefresh()
                end
            end,
            ToggleImport = function()
                if Import.Toggle then
                    Import:Toggle()
                end
            end,
            HideImport = function()
                if Import.Hide then
                    Import:Hide()
                end
            end,
        })
    end

    Bus.RegisterCallback(InternalEvents.ReservesDataChanged, function()
        module:RequestRefresh()
    end)
end

