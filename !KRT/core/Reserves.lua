local addonName, addon = ...
addon.Reserves = {}
local Reserves = addon.Reserves


		local frameName
		local LocalizeUIFrame
		local localized = false
		local UpdateUIFrame
		local updateInterval = 0.5

		local reservesData = {}
		local reservesByItemID = {}
		local reserveListFrame, scrollFrame, scrollChild
		local reserveItemRows, rowsByItemID = {}, {}
		local pendingItemInfo = {}
		local collapsedBossGroups = {}

		----------------------------------------------------------------
		-- Saved Data
		----------------------------------------------------------------
		function Reserves:Save()
			addon:Debug("DEBUG", "Saving reserves data. Entries: %d", Utils.tableLen(reservesData))
			KRT_SavedReserves = table.deepCopy(reservesData)
			KRT_SavedReserves.reservesByItemID = table.deepCopy(reservesByItemID)
		end

		function Reserves:Load()
			addon:Debug("DEBUG", "Loading reserves. Data exists: %s", tostring(KRT_SavedReserves ~= nil))
			if KRT_SavedReserves then
				reservesData = table.deepCopy(KRT_SavedReserves)
				reservesByItemID = table.deepCopy(KRT_SavedReserves.reservesByItemID or {})
			else
				reservesData = {}
				reservesByItemID = {}
			end
		end

		function Reserves:ResetSaved()
			addon:Debug("DEBUG", "Resetting saved reserves data.")
			KRT_SavedReserves = nil
			wipe(reservesData)
			wipe(reservesByItemID)
			self:RefreshWindow()
			self:CloseWindow()
			addon:Print(L.StrReserveListCleared)
		end

		function Reserves:HasData()
			return next(reservesData) ~= nil
		end

		----------------------------------------------------------------
		-- UI Windows
		----------------------------------------------------------------
		function Reserves:ShowWindow()
			if not reserveListFrame then
				addon:PrintError("Reserve List frame not available.")
				return
			end
			addon:Debug("DEBUG", "Showing reserve list window.")
			reserveListFrame:Show()
		end

		function Reserves:CloseWindow()
			addon:Debug("DEBUG", "Closing reserve list window.")
			if reserveListFrame then reserveListFrame:Hide() end
		end

		function Reserves:ShowImportBox()
			addon:Debug("DEBUG", "Opening import reserves box.")
			local frame = _G["KRTImportWindow"]
			if not frame then
				addon:PrintError("KRTImportWindow not found.")
				return
			end
			frame:Show()
			if _G["KRTImportEditBox"] then
				_G["KRTImportEditBox"]:SetText("")
			end
			_G[frame:GetName().."Title"]:SetText(format(titleString, L.StrImportReservesTitle))
		end

		function Reserves:OnLoad(frame)
			addon:Debug("DEBUG", "Reserves frame loaded.")
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
					addon:Debug("DEBUG", "Button '%s' assigned to '%s'", suff, method)
				end
			end

			LocalizeUIFrame()

			local refreshFrame = CreateFrame("Frame")
			refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
			refreshFrame:SetScript("OnEvent", function(_, _, itemId)
				addon:Debug("DEBUG", "GET_ITEM_INFO_RECEIVED for itemId %d", itemId)
				if pendingItemInfo[itemId] then
					local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
					if name then
						addon:Debug("DEBUG", "Updating reserve data for item: %s", link)
						self:UpdateReserveItemData(itemId, name, link, tex)
						pendingItemInfo[itemId] = nil
					else
						addon:Debug("DEBUG", "Item info still missing for itemId %d", itemId)
					end
				end
			end)
		end

		----------------------------------------------------------------
		-- Localization and UI Update Functions
		----------------------------------------------------------------
		-- Localize UI Frame:
		function LocalizeUIFrame()
			if localized then 
				addon:Debug("DEBUG", "UI already localized.")
				return 
			end
			if frameName then
				_G[frameName.."Title"]:SetText(format(titleString, L.StrRaidReserves))
				addon:Debug("DEBUG", "UI localized: %s", L.StrRaidReserves)
			end
			localized = true
		end

		-- Update UI Frame:
		function UpdateUIFrame(self, elapsed)
			addon:Debug("DEBUG", "UpdateUIFrame called with elapsed time: %.2f", elapsed)
			LocalizeUIFrame()
			if Utils.periodic(self, frameName, updateInterval, elapsed) then
				addon:Debug("DEBUG", "Periodic check passed for %s", frameName)
				local clearButton = _G[frameName.."ClearButton"]
				if clearButton then
					local hasData = Reserves:HasData()
					Utils.enableDisable(clearButton, hasData)
					addon:Debug("DEBUG", "ClearButton %s (HasData: %s)", hasData and "enabled" or "disabled", hasData)
				end

				local queryButton = _G[frameName.."QueryButton"]
				if queryButton then
					local hasData = Reserves:HasData()
					Utils.enableDisable(queryButton, hasData)
					addon:Debug("DEBUG", "QueryButton %s (HasData: %s)", hasData and "enabled" or "disabled", hasData)
				end
			end
		end

		----------------------------------------------------------------
		-- Reserve Data
		----------------------------------------------------------------
		-- Get specific reserve for a player:
		function Reserves:GetReserve(playerName)
			local player = playerName:lower():trim()
			local reserve = reservesData[player]

			-- Log when the function is called and show the reserve for the player
			if reserve then
				addon:Debug("DEBUG", "Found reserve for player: %s, Reserve data: %s", playerName, tostring(reserve))
			else
				addon:Debug("DEBUG", "No reserve found for player: %s", playerName)
			end

			return reserve
		end

		-- Get all reserves:
		function Reserves:GetAllReserves()
			addon:Debug("DEBUG", "Fetching all reserves. Total reserves: %d", Utils.tableLen(reservesData))
			return reservesData
		end

		-- Parse imported text
		function Reserves:ParseCSV(csv)
					addon:Debug("DEBUG", "Starting to parse CSV data.")
			wipe(reservesData)
			wipe(reservesByItemID)

			local function cleanCSVField(field)
				if not field then return nil end
				return field:gsub('^"(.-)"$', '%1'):trim()
			end

			local firstLine = true
			for line in csv:gmatch("[^\r\n]+") do
				if firstLine then
					firstLine = false
				else
					local _, itemIdStr, source, playerName, class, spec, note, plus = line:match('^"?(.-)"?,(.-),(.-),(.-),(.-),(.-),(.-),(.-)')

					-- Clean CSV field
					itemIdStr  = cleanCSVField(itemIdStr)
					source     = cleanCSVField(source)
					playerName = cleanCSVField(playerName)
					class      = cleanCSVField(class)
					spec       = cleanCSVField(spec)
					note       = cleanCSVField(note)
					plus       = cleanCSVField(plus)

					local itemId = tonumber(itemIdStr)
					local normalized = playerName and playerName:lower():trim()

					if normalized and itemId then
						-- Log the player being processed
						addon:Debug("DEBUG", "Processing player: %s, Item ID: %d", playerName, itemId)
						reservesData[normalized] = reservesData[normalized] or {
							original = playerName,
							reserves = {}
						}

						local found = false
						for _, entry in ipairs(reservesData[normalized].reserves) do
							if entry.rawID == itemId then
								entry.quantity = (entry.quantity or 1) + 1
								found = true
								addon:Debug("DEBUG", "Updated quantity for player %s, item ID %d. New quantity: %d", playerName, itemId, entry.quantity)
								break
							end
						end

						if not found then
							local entry = {
								rawID     = itemId,
								itemLink  = nil,
								itemName  = nil,
								itemIcon  = nil,
								quantity  = 1,
								class     = class ~= "" and class or nil,
								note      = note ~= "" and note or nil,
								plus      = tonumber(plus) or 0,
								source    = source ~= "" and source or nil
							}
							tinsert(reservesData[normalized].reserves, entry)
							reservesByItemID[itemId] = reservesByItemID[itemId] or {}
							tinsert(reservesByItemID[itemId], entry)
							-- Log new reserve entry added
							addon:Debug("DEBUG", "Added new reserve entry for player %s, item ID %d", playerName, itemId)
						end
					end
				end
			end
			-- Log when the CSV parsing is completed
			addon:Debug("DEBUG", "Finished parsing CSV data. Total reserves processed: %d", Utils.tableLen(reservesData))

			self:RefreshWindow()
			self:Save()
		end

		----------------------------------------------------------------
		-- Query / Tooltip
		----------------------------------------------------------------
		-- Query for item info
		function Reserves:QueryItemInfo(itemId)
			if not itemId then return end
			addon:Debug("DEBUG", "Querying info for itemId: %d", itemId)
			local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
			if name and link and tex then
				self:UpdateReserveItemData(itemId, name, link, tex)
				addon:Debug("DEBUG", "Successfully queried info for itemId: %d, Item Name: %s", itemId, name)
				return true
			else
				GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
				GameTooltip:SetHyperlink("item:" .. itemId)
				GameTooltip:Hide()
				addon:Debug("DEBUG", "Failed to query info for itemId: %d", itemId)
				return false
			end
		end

		-- Query all missing items for reserves
		function Reserves:QueryMissingItems()
			local count = 0
			addon:Debug("DEBUG", "Querying missing items in reserves.")
			for _, player in pairs(reservesData) do
				if type(player) == "table" and type(player.reserves) == "table" then
					for _, r in ipairs(player.reserves) do
						if not r.itemLink or not r.itemIcon then
							if not self:QueryItemInfo(r.rawID) then
								count = count + 1
							end
						end
					end
				end
			end
			addon:Print(count > 0 and ("Requested info for " .. count .. " missing items.") or "All item infos are available.")
			addon:Debug("DEBUG", "Total missing items requested: %d", count)
		end

		-- Update reserve item data
		function Reserves:UpdateReserveItemData(itemId, itemName, itemLink, itemIcon)
			addon:Debug("DEBUG", "Updating reserve item data for itemId: %d", itemId)
			for _, player in pairs(reservesData) do
				if type(player) == "table" and type(player.reserves) == "table" then
					for _, r in ipairs(player.reserves or {}) do
						if r.rawID == itemId then
							r.itemName = itemName
							r.itemLink = itemLink
							r.itemIcon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
							addon:Debug("DEBUG", "Updated reserve data for player: %s, itemId: %d", player.original, itemId)
						end
					end
				end
			end

			local rows = rowsByItemID[itemId]
			if not rows then return end

			for _, row in ipairs(rows) do
				local icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
				row.icon:SetTexture(icon)

				if row.quantityText then
					if row.quantityText:GetText() and row.quantityText:GetText():match("^%d+x$") then
						row.quantityText:SetText(row.quantityText:GetText()) -- Preserve format
					end
				end

				local tooltipText = itemLink or itemName or ("Item ID: " .. itemId)
				row.nameText:SetText(tooltipText)

				row.iconBtn:SetScript("OnEnter", function()
					GameTooltip:SetOwner(row.iconBtn, "ANCHOR_RIGHT")
					if itemLink then
						GameTooltip:SetHyperlink(itemLink)
					else
						GameTooltip:SetText("Item ID: " .. itemId, 1, 1, 1)
					end
					GameTooltip:Show()
				end)

				row.iconBtn:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
			end
		end

		-- Get reserve count for a specific item for a player
		function Reserves:GetReserveCountForItem(itemId, playerName)
			local normalized = playerName and playerName:lower()
			local entry = reservesData[normalized]
			if not entry then return 0 end
			addon:Debug("DEBUG", "Checking reserve count for itemId: %d for player: %s", itemId, playerName)
			for _, r in ipairs(entry.reserves or {}) do
				if r.rawID == itemId then
					addon:Debug("DEBUG", "Found reserve for itemId: %d, player: %s, quantity: %d", itemId, playerName, r.quantity)
					return r.quantity or 1
				end
			end
			addon:Debug("DEBUG", "No reserve found for itemId: %d, player: %s", itemId, playerName)
			return 0
		end

		----------------------------------------------------------------
		-- Display / Table Rendering
		----------------------------------------------------------------
		function Reserves:RefreshWindow()
			addon:Debug("DEBUG", "Refreshing reserve window.")
			if not reserveListFrame or not scrollChild then return end

			-- Hide and clear old rows
			for _, row in ipairs(reserveItemRows) do row:Hide() end
			wipe(reserveItemRows)
			wipe(rowsByItemID)

			-- Group reserves by item source, ID, and quantity
			local grouped = {}
			for _, player in pairs(reservesData) do
				for _, r in ipairs(player.reserves or {}) do
					local key = (r.source or "Unknown") .. "||" .. r.rawID .. "||" .. (r.quantity or 1)
					grouped[key] = grouped[key] or {
						itemId = r.rawID,
						quantity = r.quantity or 1,
						itemLink = r.itemLink,
						itemName = r.itemName,
						itemIcon = r.itemIcon,
						source = r.source or "Unknown",
						players = {}
					}
					tinsert(grouped[key].players, player.original)
				end
			end

			-- Sort the grouped reserves
			local displayList = {}
			for _, data in pairs(grouped) do
				tinsert(displayList, data)
			end
			table.sort(displayList, function(a, b)
				if a.source ~= b.source then return a.source < b.source end
				if a.itemId ~= b.itemId then return a.itemId < b.itemId end
				return a.quantity < b.quantity
			end)

			local rowHeight, yOffset = 34, 0
			local seenSources = {}

			-- Create headers and reserve rows
			for index, entry in ipairs(displayList) do
				local source = entry.source

				-- Log for new source groups
				if not seenSources[source] then
					seenSources[source] = true
					addon:Debug("DEBUG", "New source found: %s", source)
					if collapsedBossGroups[source] == nil then
						collapsedBossGroups[source] = false
					end

					local headerBtn = CreateFrame("Button", nil, scrollChild)
					headerBtn:SetSize(320, 28)
					headerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)

					local fullLabel = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
					fullLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
					fullLabel:SetTextColor(1, 0.82, 0)
					local prefix = collapsedBossGroups[source] and "|TInterface\\Buttons\\UI-PlusButton-Up:12|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "
					fullLabel:SetText(prefix .. source)
					fullLabel:SetPoint("CENTER", headerBtn, "CENTER", 0, 0)

					local leftLine = headerBtn:CreateTexture(nil, "ARTWORK")
					leftLine:SetTexture("Interface\\Buttons\\WHITE8x8")
					leftLine:SetVertexColor(1, 1, 1, 0.3)
					leftLine:SetHeight(1)
					leftLine:SetPoint("RIGHT", fullLabel, "LEFT", -6, 0)
					leftLine:SetPoint("LEFT", headerBtn, "LEFT", 4, 0)

					local rightLine = headerBtn:CreateTexture(nil, "ARTWORK")
					rightLine:SetTexture("Interface\\Buttons\\WHITE8x8")
					rightLine:SetVertexColor(1, 1, 1, 0.3)
					rightLine:SetHeight(1)
					rightLine:SetPoint("LEFT", fullLabel, "RIGHT", 6, 0)
					rightLine:SetPoint("RIGHT", headerBtn, "RIGHT", -4, 0)

					-- Click toggle
					headerBtn:SetScript("OnClick", function()
						collapsedBossGroups[source] = not collapsedBossGroups[source]
						addon:Debug("DEBUG", "Toggling collapse state for source: %s to %s", source, tostring(collapsedBossGroups[source]))
						Reserves:RefreshWindow()
					end)

					tinsert(reserveItemRows, headerBtn)
					yOffset = yOffset + 24
				end

				-- Log for rows that are added
				if not collapsedBossGroups[source] then
					addon:Debug("DEBUG", "Adding row for itemId: %d, source: %s", entry.itemId, source)
					local row = Reserves:CreateReserveRow(scrollChild, entry, yOffset, index)
					tinsert(reserveItemRows, row)
					yOffset = yOffset + rowHeight
				end
			end

			-- Update the scrollable area
			scrollChild:SetHeight(yOffset)
			scrollFrame:SetVerticalScroll(0)
		end

		-- Create a new row for displaying a reserve
		function Reserves:CreateReserveRow(parent, info, yOffset, index)
			addon:Debug("DEBUG", "Creating reserve row for itemId: %d", info.itemId)
			local row = CreateFrame("Frame", nil, parent)
			row:SetSize(320, 34)
			row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
			row._rawID = info.itemId

			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(row)
			bg:SetTexture("Interface\\Buttons\\WHITE8x8")
			bg:SetVertexColor(index % 2 == 0 and 0.1 or 0, 0.1, 0.1, 0.3)

			local icon = row:CreateTexture(nil, "ARTWORK")
			icon:SetSize(32, 32)
			icon:SetPoint("LEFT", row, "LEFT", 0, 0)

			local iconBtn = CreateFrame("Button", nil, row)
			iconBtn:SetAllPoints(icon)

			local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
			nameText:SetText(info.itemLink or info.itemName or ("[Item " .. info.itemId .. "]"))

			local playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			playerText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
			playerText:SetText(table.concat(info.players or {}, ", "))

			local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			quantityText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
			quantityText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
			quantityText:SetTextColor(1, 1, 1)

			if info.quantity and info.quantity > 1 then
				quantityText:SetText(info.quantity .. "x")
				quantityText:Show()
			else
				quantityText:Hide()
			end

			icon:SetTexture(info.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

			iconBtn:SetScript("OnEnter", function()
				GameTooltip:SetOwner(iconBtn, "ANCHOR_RIGHT")
				if info.itemLink then
					GameTooltip:SetHyperlink(info.itemLink)
				else
					GameTooltip:SetText("Item ID: " .. info.itemId, 1, 1, 1)
				end
				if info.source then
					GameTooltip:AddLine("Dropped by: " .. info.source, 0.8, 0.8, 0.8)
				end
				GameTooltip:Show()
			end)

			iconBtn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			row.icon = icon
			row.iconBtn = iconBtn
			row.nameText = nameText
			row.quantityText = quantityText

			row:Show()
			rowsByItemID[info.itemId] = rowsByItemID[info.itemId] or {}
			tinsert(rowsByItemID[info.itemId], row)

			return row
		end

		----------------------------------------------------------------
		-- SR Announcement
		----------------------------------------------------------------
		function Reserves:GetPlayersForItem(itemId)
			addon:Debug("DEBUG", "Getting players for itemId: %d", itemId)
			local players = {}
			-- Loop through each player and their reserves
			for _, player in pairs(reservesData or {}) do
				for _, r in ipairs(player.reserves or {}) do
					if r.rawID == itemId then
						local qty = r.quantity or 1
						local display = qty > 1 and ("(" .. qty .. "x)" .. player.original) or player.original
						tinsert(players, display)
						-- Log when a player is added for an item
						addon:Debug("DEBUG", "Added player %s with quantity %d for itemId %d", player.original, qty, itemId)
						break
					end
				end
			end
			addon:Debug("DEBUG", "Returning %d players for itemId %d", #players, itemId)
			return players
		end

		function Reserves:FormatReservedPlayersLine(itemId)
			addon:Debug("DEBUG", "Formatting reserved players line for itemId: %d", itemId)
			local list = self:GetPlayersForItem(itemId)
			-- Log the list of players found for the item
			addon:Debug("DEBUG", "Players for itemId %d: %s", itemId, table.concat(list, ", "))
			return #list > 0 and table.concat(list, ", ") or ""
		end

