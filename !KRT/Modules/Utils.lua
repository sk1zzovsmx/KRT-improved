local addonName, addon = ...
addon.Utils = addon.Utils or {}

local Utils = addon.Utils
local L = addon.L

local type, ipairs = type, ipairs
local floor, random = math.floor, math.random
local find = string.find
local format, gsub = string.format, string.gsub
local strsub, strlen = string.sub, string.len
local lower, upper = string.lower, string.upper
local select = select
local twipe = table.wipe
local LibStub = LibStub
local CreateFrame = CreateFrame

local GetTime = GetTime
local GetRealmName = GetRealmName
local GetAchievementLink = GetAchievementLink
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader

local ITEM_LINK_FORMAT = "|c%s|Hitem:%d:%s|h[%s]|h|r"

-- =========== Global convenience helpers (kept as-is)  =========== --

-- Shuffle a table:
_G.table.shuffle = function(t)
	local n = #t
	while n > 1 do
		local k = random(1, n)
		t[n], t[k] = t[k], t[n]
		n = n - 1
	end
end

-- Reverse table:
_G.table.reverse = function(t, count)
	local i, j = 1, #t
	while i < j do
		t[i], t[j] = t[j], t[i]
		i = i + 1
		j = j - 1
	end
end

-- Trim a string:
_G.string.trim = function(str)
	return gsub(str, "^%s*(.-)%s*$", "%1")
end

-- String starts with:
_G.string.startsWith = function(str, piece)
	return strsub(str, 1, strlen(piece)) == piece
end

-- String ends with:
_G.string.endsWith = function(str, piece)
	-- Check whether a string ends with the provided piece. Fails gracefully if inputs are not strings.
	if type(str) ~= "string" or type(piece) ~= "string" then
		return false
	end
	local lenPiece = strlen(piece)
	-- If the main string is shorter than the piece, it cannot end with it.
	if #str < lenPiece then
		return false
	end
	return strsub(str, -lenPiece) == piece
end


-- =========== Debug/state helpers  =========== --

function Utils.applyDebugSetting(enabled)
	local options = addon and addon.options
	if options then
		options.debug = enabled and true or false
	end

	local level
	if enabled then
		local levels = addon and addon.Debugger and addon.Debugger.logLevels
		level = levels and levels.DEBUG
	else
		local levels = addon and addon.Debugger and addon.Debugger.logLevels
		level = levels and levels.INFO
	end

	if level and addon and addon.SetLogLevel then
		addon:SetLogLevel(level)
	end
end

function Utils.getPlayerName()
	addon.State = addon.State or {}
	addon.State.player = addon.State.player or {}
	local name = addon.State.player.name
		or addon.UnitFullName("player")
	addon.State.player.name = name
	return name
end

-- =========== String helpers  =========== --

function Utils.ucfirst(value)
	if type(value) ~= "string" then
		value = tostring(value or "")
	end
	value = lower(value)
	return gsub(value, "%a", upper, 1)
end

function Utils.trimText(value, allowNil)
	if value == nil then
		return allowNil and nil or ""
	end
	return tostring(value):trim()
end

function Utils.normalizeName(value, allowNil)
	local text = Utils.trimText(value, allowNil)
	if text == nil then
		return nil
	end
	return Utils.ucfirst(text)
end

function Utils.normalizeLower(value, allowNil)
	local text = Utils.trimText(value, allowNil)
	if text == nil then
		return nil
	end
	return lower(text)
end

function Utils.findAchievement(inp)
	local out = inp and inp:trim() or ""
	if out ~= "" and find(out, "%{%d*%}") then
		local b, e = find(out, "%{%d*%}")
		local id = strsub(out, b + 1, e - 1)
		local link = (id and id ~= "" and GetAchievementLink(id)) or ("[" .. id .. "]")
		out = strsub(out, 1, b - 1) .. link .. strsub(out, e + 1)
	end
	return out
end

function Utils.formatChatMessage(text, prefix, outputFormat, prefixHex)
	local msgPrefix = prefix or ""
	if prefixHex then
		msgPrefix = addon.WrapTextInColorCode(msgPrefix, Utils.normalizeHexColor(prefixHex))
	end
	return format(outputFormat or "%s%s", msgPrefix, tostring(text))
end

function Utils.splitArgs(msg)
	msg = Utils.trimText(msg)
	if msg == "" then
		return "", ""
	end
	local cmd, rest = msg:match("^(%S+)%s*(.-)$")
	return Utils.normalizeLower(cmd), Utils.trimText(rest)
end

function Utils.getItemIdFromLink(itemLink)
	if not itemLink then return nil end
	local _, itemId = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
	return itemId
end

-- Extract a stable "itemString" identifier from an item link.
--
-- This is safer than using only itemId because it preserves meaningful
-- link fields (e.g. random suffix / uniqueId) when present.
function Utils.getItemStringFromLink(itemLink)
	if type(itemLink) ~= "string" or itemLink == "" then
		return nil
	end

	-- Fast-path: capture the raw itemString from the hyperlink.
	-- Includes potential negative numbers (suffix IDs) in WotLK links.
	local itemString = itemLink:match("|H(item:[%-%d:]+)|h")
	if itemString then
		return itemString
	end

	-- Fallback: use LibDeformat pattern used elsewhere in the addon.
	local _, itemId, rest = addon.Deformat(itemLink, ITEM_LINK_FORMAT)
	if itemId then
		if rest and rest ~= "" then
			return "item:" .. tostring(itemId) .. ":" .. tostring(rest)
		end
		return "item:" .. tostring(itemId)
	end

	return nil
end

-- =========== UI helpers  =========== --

--
-- createRowDrawer(fn)
--
-- Wraps a row drawing function with logic to cache and return the row height.
-- Each invocation of this helper returns a new closure with its own cached
-- height. The supplied callback should perform any per-row UI updates but
-- MUST NOT return a value; the wrapper will return the cached height on
-- each call.
--
-- Example:
--   drawRow = Utils.createRowDrawer(function(row, it)
--       local ui = row._p
--       ui.ID:SetText(it.id)
--   end)
function Utils.createRowDrawer(fn)
	local rowHeight
	return function(row, it)
		if not rowHeight then
			rowHeight = (row and row:GetHeight()) or 20
		end
		fn(row, it)
		return rowHeight
	end
end

-- =========== List controller helper  =========== --
-- Generic scroll list controller with row pooling, sorting, and selection visuals.
function Utils.makeListController(cfg)
	local self = {
		frameName = nil,
		data = {},
		_rows = {},
		_rowByName = {},
		_asc = false,
		_lastHL = nil,
		_active = false,
		_localized = false,
		_lastWidth = nil,
		_dirty = true,
	}

	local defer = CreateFrame("Frame")
	defer:Hide()

	local function buildRowParts(btnName, row)
		if cfg._rowParts and not row._p then
			local p = {}
			for i = 1, #cfg._rowParts do
				local part = cfg._rowParts[i]
				p[part] = _G[btnName .. part]
			end
			row._p = p
		end
	end

	local function acquireRow(btnName, parent)
		local row = self._rowByName[btnName]
		if row then
			row:Show()
			if Utils and Utils.ensureRowVisuals then
				Utils.ensureRowVisuals(row)
			end
			return row
		end

		row = CreateFrame("Button", btnName, parent, cfg.rowTmpl)
		self._rowByName[btnName] = row
		buildRowParts(btnName, row)
		if Utils and Utils.ensureRowVisuals then
			Utils.ensureRowVisuals(row)
		end
		return row
	end

	local function releaseData()
		for i = 1, #self.data do
			twipe(self.data[i])
		end
		twipe(self.data)
	end

	local function refreshData()
		releaseData()
		if cfg.getData then
			cfg.getData(self.data)
		end
	end

	local function ensureLocalized()
		if not self._localized and cfg.localize then
			cfg.localize(self.frameName)
			self._localized = true
		end
	end

	local function setActive(active)
		self._active = active
		if self._active then
			ensureLocalized()
			-- Reset one-shot diagnostics each time the list becomes active (OnShow).
			self._loggedFetch = nil
			self._loggedWidgets = nil
			self._warnW0 = nil
			self._missingScroll = nil
			self:Dirty()
			return
		end
		releaseData()
		for i = 1, #self._rows do
			local row = self._rows[i]
			if row then row:Hide() end
		end
		self._lastHL = nil
	end

	local function applyHighlight()
		-- Selection overlay (multi or legacy single) + Focus border (one row).
		-- Keep hover highlight native (no LockHighlight for selection).
		local focusId = (cfg.focusId and cfg.focusId()) or (cfg.highlightId and cfg.highlightId()) or nil

		local selKey
		if cfg.highlightId then
			-- Legacy: single selection (use the selected id as key)
			local sel = cfg.highlightId()
			selKey = sel and ("id:" .. tostring(sel)) or "id:nil"
		elseif cfg.highlightFn then
			selKey = (cfg.highlightKey and cfg.highlightKey()) or false
		else
			selKey = false
		end

		local focusKey = (cfg.focusKey and cfg.focusKey()) or
			(focusId ~= nil and ("f:" .. tostring(focusId)) or "f:nil")
		local combo = tostring(selKey) .. "|" .. tostring(focusKey)
		if combo == self._lastHL then return end
		self._lastHL = combo

		for i = 1, #self.data do
			local it = self.data[i]
			local row = self._rows[i]
			if row then
				local isSel = false
				if cfg.highlightId then
					local sel = cfg.highlightId()
					isSel = (sel ~= nil and it.id == sel)
				elseif cfg.highlightFn then
					isSel = cfg.highlightFn(it.id, it, i, row) and true or false
				end

				if Utils and Utils.setRowSelected then
					Utils.setRowSelected(row, isSel)
				else
					-- Fallback to legacy highlight if visuals are missing.
					Utils.toggleHighlight(row, isSel)
				end

				if Utils and Utils.setRowFocused then
					Utils.setRowFocused(row, focusId ~= nil and it.id == focusId)
				end
			end
		end

		if cfg.highlightDebugTag and addon and addon.options and addon.options.debug and addon.debug then
			local info = (cfg.highlightDebugInfo and cfg.highlightDebugInfo(self)) or ""
			if info ~= "" then info = " " .. info end
			addon:debug(("[%s] refresh key=%s%s"):format(tostring(cfg.highlightDebugTag), tostring(selKey), info))
		end
	end

	local function postUpdate()
		if cfg.postUpdate then
			cfg.postUpdate(self.frameName)
		end
	end

	function self:Touch()
		defer:Show()
	end

	function self:Dirty()
		self._dirty = true
		defer:Show()
	end

	local function runUpdate()
		if not self._active or not self.frameName then return end

		if self._dirty then
			refreshData()
			local okFetch = self:Fetch()
			-- If Fetch() returns false we defer until the frame has a real size.
			if okFetch ~= false then
				self._dirty = false
			end
		end

		applyHighlight()
		postUpdate()
	end

	defer:SetScript("OnUpdate", function(f)
		f:Hide()
		local ok, err = pcall(runUpdate)
		if not ok then
			-- If the user has script errors disabled, this still surfaces the problem in chat.
			if err ~= self._lastErr then
				self._lastErr = err
				addon:error(L.LogLoggerUIError:format(tostring(cfg.keyName or "?"), tostring(err)))
			end
		end
	end)

	function self:OnLoad(frame)
		if not frame then return end
		self.frameName = frame:GetName()

		frame:SetScript("OnShow", function()
			if not self._shownOnce then
				self._shownOnce = true
				addon:debug(L.LogLoggerUIShow:format(tostring(cfg.keyName or "?"), tostring(self.frameName)))
			end
			setActive(true)
			if not self._loggedWidgets then
				self._loggedWidgets = true
				local n = self.frameName
				local sf = n and _G[n .. "ScrollFrame"]
				local sc = n and _G[n .. "ScrollFrameScrollChild"]
				addon:debug(L.LogLoggerUIWidgets:format(
					tostring(cfg.keyName or "?"),
					tostring(sf), tostring(sc),
					sf and (sf:GetWidth() or 0) or 0,
					sf and (sf:GetHeight() or 0) or 0,
					sc and (sc:GetWidth() or 0) or 0,
					sc and (sc:GetHeight() or 0) or 0
				))
			end
		end)

		frame:SetScript("OnHide", function()
			setActive(false)
		end)

		if frame:IsShown() then
			setActive(true)
		end
	end

	function self:Fetch()
		local n = self.frameName
		if not n then return end

		local sf = _G[n .. "ScrollFrame"]
		local sc = _G[n .. "ScrollFrameScrollChild"]
		if not (sf and sc) then
			if not self._missingScroll then
				self._missingScroll = true
				addon:warn(L.LogLoggerUIMissingWidgets:format(tostring(cfg.keyName or "?"), tostring(n)))
			end
			return
		end

		local scrollW = sf:GetWidth() or 0
		self._lastWidth = scrollW

		-- Defer draw until the ScrollFrame has a real size (first OnShow can report 0).
		if scrollW < 10 then
			if not self._warnW0 then
				self._warnW0 = true
				addon:debug(L.LogLoggerUIDeferLayout:format(tostring(cfg.keyName or "?"), scrollW))
			end
			defer:Show()
			return false
		end
		if (sc:GetWidth() or 0) < 10 then
			sc:SetWidth(scrollW)
		end

		-- One-time diagnostics per list to help debug "empty/blank" frames.
		if not self._loggedFetch then
			self._loggedFetch = true
			addon:debug(L.LogLoggerUIFetch:format(
				tostring(cfg.keyName or "?"),
				#self.data,
				sf:GetWidth() or 0, sf:GetHeight() or 0,
				sc:GetWidth() or 0, sc:GetHeight() or 0,
				(_G[n] and _G[n]:GetWidth() or 0),
				(_G[n] and _G[n]:GetHeight() or 0)
			))
		end

		local totalH = 0
		local count = #self.data

		for i = 1, count do
			local it = self.data[i]
			local btnName = cfg.rowName(n, it, i)

			local row = self._rows[i]
			if not row or row:GetName() ~= btnName then
				row = acquireRow(btnName, sc)
				self._rows[i] = row
			end

			row:SetID(it.id)
			row:ClearAllPoints()
			-- Stretch the row to the scrollchild width.
			-- (Avoid relying on GetWidth() being valid on the first OnShow frame.)
			row:SetPoint("TOPLEFT", 0, -totalH)
			row:SetPoint("TOPRIGHT", -20, -totalH)

			local rH = cfg.drawRow(row, it)
			local usedH = rH or row:GetHeight() or 20
			totalH = totalH + usedH

			row:Show()
		end

		for i = count + 1, #self._rows do
			local r = self._rows[i]
			if r then r:Hide() end
		end

		sc:SetHeight(math.max(totalH, sf:GetHeight()))
		if sf.UpdateScrollChildRect then
			sf:UpdateScrollChildRect()
		end
		self._lastHL = nil
	end

	function self:Sort(key)
		local cmp = cfg.sorters and cfg.sorters[key]
		if not cmp or #self.data <= 1 then return end
		self._asc = not self._asc
		table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
		self:Fetch()
		applyHighlight()
		postUpdate()
	end

	self._makeConfirmPopup = Utils.makeConfirmPopup

	return self
end

function Utils.bindListController(module, controller)
	module.OnLoad = function(_, frame) controller:OnLoad(frame) end
	module.Fetch = function() controller:Fetch() end
	module.Sort = function(_, t) controller:Sort(t) end
end

-- =========== Roster helpers  =========== --

function Utils.getRealmName()
	local realm = GetRealmName()
	if type(realm) ~= "string" then
		return ""
	end
	return realm
end

function Utils.getUnitRank(unit, fallback)
	local groupLeader = (addon and addon.UnitIsGroupLeader) or UnitIsGroupLeader
	local groupAssistant = (addon and addon.UnitIsGroupAssistant) or UnitIsGroupAssistant

	if groupLeader and groupLeader(unit) then
		return 2
	end
	if groupAssistant and groupAssistant(unit) then
		return 1
	end
	return fallback or 0
end

-- =========== Callback utilities  =========== --

do
	local CallbackHandler = LibStub("CallbackHandler-1.0") -- vendored (hard dependency)

	-- Internal callback registry (not the WoW event registry)
	addon.InternalCallbacksTarget = addon.InternalCallbacksTarget or {}
	addon.InternalCallbacks = addon.InternalCallbacks
		or CallbackHandler:New(addon.InternalCallbacksTarget, "RegisterCallback", "UnregisterCallback",
			"UnregisterAllCallbacks")

	local target = addon.InternalCallbacksTarget
	local registry = addon.InternalCallbacks

	-- Register a callback for an internal event.
	-- Returns a handle you can use to unregister later (optional).
	function Utils.registerCallback(e, func)
		if not e or type(func) ~= "function" then
			error(L.StrCbErrUsage)
		end

		-- CallbackHandler uses "self" as the uniqueness key; use a unique token per registration
		-- to allow multiple anonymous listeners on the same event (same behavior as the old table).
		local token = {}

		-- Preserve existing signature + safety: listener receives (eventName, ...)
		local wrapped = function(eventName, ...)
			local ok, err = pcall(func, eventName, ...)
			if not ok then
				addon:error(L.StrCbErrExec:format(tostring(func), tostring(eventName), err))
			end
		end

		target.RegisterCallback(token, e, wrapped)
		return { e = e, t = token }
	end

	-- Optional: unregister a previously registered callback handle.
	-- (Non-breaking: if you never call it, nothing changes for current code.)
	function Utils.unregisterCallback(handle)
		if type(handle) ~= "table" or not handle.e or not handle.t then return end
		target.UnregisterCallback(handle.t, handle.e)
	end

	-- Fire an internal event; callbacks receive (eventName, ...).
	function Utils.triggerEvent(e, ...)
		registry:Fire(e, ...)
	end

	function Utils.registerCallbacks(names, handler)
		for i = 1, #names do
			Utils.registerCallback(names[i], handler)
		end
	end
end

-- =========== Frame helpers  =========== --

function Utils.getFrameName()
	return addon.UIMaster:GetName()
end

function Utils.makeConfirmPopup(key, text, onAccept, cancels)
	StaticPopupDialogs[key] = {
		text = text,
		button1 = OKAY,
		button2 = CANCEL,
		OnAccept = onAccept,
		cancels = cancels or key,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}
end

function Utils.makeEditBoxPopup(key, text, onAccept, onShow, validate)
	StaticPopupDialogs[key] = {
		text = text,
		button1 = SAVE,
		button2 = CANCEL,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		hasEditBox = 1,
		cancels = key,
		OnShow = function(self)
			if onShow then
				onShow(self)
			end
		end,
		OnHide = function(self)
			self.editBox:SetText("")
			self.editBox:ClearFocus()
		end,
		OnAccept = function(self)
			local value = Utils.trimText(self.editBox:GetText(), true)
			if validate then
				local ok, cleanValue = validate(self, value)
				if not ok then
					return
				end
				if cleanValue ~= nil then
					value = cleanValue
				end
			end
			onAccept(self, value)
		end,
	}
end

function Utils.setFrameTitle(frameOrName, titleText, titleFormat)
	local frameName = frameOrName
	if type(frameOrName) ~= "string" then
		frameName = frameOrName and frameOrName.GetName and frameOrName:GetName() or nil
	end
	if not frameName then return end
	local titleFrame = _G[frameName .. "Title"]
	if not titleFrame then return end
	local fmt = titleFormat or (addon.C and addon.C.titleString) or "%s"
	titleFrame:SetText(format(fmt, titleText))
end

function Utils.resetEditBox(editBox, hide)
	if not editBox then return end
	editBox:SetText("")
	editBox:ClearFocus()
	if hide then
		editBox:Hide()
	end
end

function Utils.setEditBoxValue(editBox, value, focus)
	if not editBox then return end
	editBox:SetText(value)
	editBox:Show()
	if focus then
		editBox:SetFocus()
	end
end

function Utils.setShown(frame, show)
	if not frame then return end
	if show then
		if not frame:IsShown() then
			frame:Show()
		end
	elseif frame:IsShown() then
		frame:Hide()
	end
end

-- =========== Tooltip helpers  =========== --

do
	local colors = HIGHLIGHT_FONT_COLOR

	local function showTooltip(frame)
		if not frame.tooltip_anchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, frame)
		else
			GameTooltip:SetOwner(frame, frame.tooltip_anchor)
		end

		if frame.tooltip_title then
			GameTooltip:SetText(frame.tooltip_title)
		end

		if frame.tooltip_text then
			if type(frame.tooltip_text) == "string" then
				GameTooltip:AddLine(frame.tooltip_text, colors.r, colors.g, colors.b, true)
			elseif type(frame.tooltip_text) == "table" then
				for _, line in ipairs(frame.tooltip_text) do
					GameTooltip:AddLine(line, colors.r, colors.g, colors.b, true)
				end
			end
		end

		if frame.tooltip_item then
			GameTooltip:SetHyperlink(frame.tooltip_item)
		end

		GameTooltip:Show()
	end

	local function hideTooltip()
		GameTooltip:Hide()
	end

	function addon:SetTooltip(frame, text, anchor, title)
		if not frame then return end
		frame.tooltip_text = text and text or frame.tooltip_text
		frame.tooltip_anchor = anchor and anchor or frame.tooltip_anchor
		frame.tooltip_title = title and title or frame.tooltip_title
		if not frame.tooltip_title and not frame.tooltip_text and not frame.tooltip_item then return end
		frame:SetScript("OnEnter", showTooltip)
		frame:SetScript("OnLeave", hideTooltip)
	end
end

-- =========== Color utilities  =========== --

function Utils.normalizeHexColor(color)
	if type(color) == "string" then
		local hex = color:gsub("^|c", ""):gsub("|r$", ""):gsub("^#", "")
		if #hex == 6 then
			hex = "ff" .. hex
		end
		return hex
	end

	if type(color) == "table" and color.GenerateHexColor then
		local hex = color:GenerateHexColor():gsub("^#", "")
		if #hex == 6 then
			hex = "ff" .. hex
		end
		return hex
	end

	return "ffffffff"
end

function Utils.getClassColor(className)
	local r, g, b = addon.GetClassColor(className)
	return (r or 1), (g or 1), (b or 1)
end

-- =========== UI helpers  =========== --

-- Enable/Disable Frame:
function Utils.enableDisable(frame, cond)
	if cond and frame:IsEnabled() == 0 then
		frame:Enable()
	elseif not cond and frame:IsEnabled() == 1 then
		frame:Disable()
	end
end

-- Unconditional show/hide frame:
function Utils.toggle(frame)
	if frame:IsVisible() then
		frame:Hide()
	else
		frame:Show()
	end
end

-- Hide frame with optional onHide callback:
function Utils.hideFrame(frame, onHide)
	if frame and frame:IsShown() then
		if onHide then onHide() end
		frame:Hide()
	end
end

-- Conditional Show/Hide Frame:
function Utils.showHide(frame, cond)
	if cond and not frame:IsShown() then
		frame:Show()
	elseif not cond and frame:IsShown() then
		frame:Hide()
	end
end

-- Lock or unlock highlight:
function Utils.toggleHighlight(frame, cond)
	if cond then
		frame:LockHighlight()
	else
		frame:UnlockHighlight()
	end
end

-- =========== List row visuals (selection/focus)  =========== --
-- These helpers avoid using LockHighlight() for persistent selection, so hover highlight remains native.
-- Safe for 3.3.5a and works with any UI skin (pure texture overlays).

local function _ensureRowVisuals(row)
	if not row or row._krtSelTex then return end

	-- Persistent selection fill (soft)
	local sel = row:CreateTexture(nil, "BACKGROUND")
	sel:SetAllPoints(row)
	-- Persistent selection highlight (soft). Uses a Blizzard highlight texture so it reads as "highlight",
	-- while staying independent from the native mouseover HighlightTexture.
	sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	sel:SetBlendMode("ADD")
	-- Slightly more pronounced than mouseover.
	sel:SetVertexColor(0.20, 0.60, 1.00, 0.52)
	sel:Hide()
	row._krtSelTex = sel

	-- Focus highlight (stronger). Still a highlight, not a border.
	local focus = row:CreateTexture(nil, "ARTWORK")
	focus:SetAllPoints(row)
	focus:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	focus:SetBlendMode("ADD")
	focus:SetVertexColor(0.20, 0.60, 1.00, 0.72)
	focus:Hide()
	row._krtFocusTex = focus

	-- Pushed feedback (mouse down)
	local pushed = row:CreateTexture(nil, "ARTWORK")
	pushed:SetAllPoints(row)
	pushed:SetTexture(1, 1, 1, 0.08)
	row:SetPushedTexture(pushed)
end

function Utils.ensureRowVisuals(row)
	_ensureRowVisuals(row)
end

function Utils.setRowSelected(row, cond)
	_ensureRowVisuals(row)
	if not row or not row._krtSelTex then return end
	if cond then row._krtSelTex:Show() else row._krtSelTex:Hide() end
end

function Utils.setRowFocused(row, cond)
	_ensureRowVisuals(row)
	local t = row and row._krtFocusTex
	if not t then return end
	if cond then t:Show() else t:Hide() end
end

-- Helper: append "(N)" to a button label, preserving the original base label.
function Utils.setButtonCount(btn, baseText, n)
	if not btn then return end
	if not btn._krtBaseText then
		btn._krtBaseText = baseText or btn:GetText() or ""
	end
	local base = baseText or btn._krtBaseText or ""
	if n and n > 1 then
		btn:SetText(("%s (%d)"):format(base, n))
	else
		btn:SetText(base)
	end
end

-- =========== Multi-select utility (reusable)  =========== --
-- Runtime-only selection state for scrollable lists.
-- State is keyed by "contextKey" (string) so multiple lists can coexist.

-- Runtime-only selection state for scrollable lists.
-- State is keyed by "contextKey" (string) so multiple lists can coexist.
-- IMPORTANT: bind the backing table to a *local* upvalue in the file chunk.
-- This avoids accidental global lookups (e.g. "MS" becoming nil at runtime).

Utils._multiSelect = Utils._multiSelect or {}
local MS = Utils._multiSelect

do
	local function _msKey(id)
		if id == nil then return nil end
		local n = tonumber(id)
		return n or id
	end

	local function _ensure(contextKey)
		if not contextKey or contextKey == "" then
			contextKey = "_default"
		end
		local st = MS[contextKey]
		if not st then
			st = { set = {}, count = 0, ver = 0 }
			MS[contextKey] = st
		end
		return st, contextKey
	end

	local function _dbg(msg)
		if addon and addon.options and addon.options.debug and addon.debug then
			addon:debug(msg)
		end
	end

	function Utils.MultiSelect_Init(contextKey)
		local st, key = _ensure(contextKey)
		st.set = {}
		st.count = 0
		st.ver = (st.ver or 0) + 1
		_dbg(("[LoggerSelect] init ctx=%s ver=%d"):format(tostring(key), st.ver))
		return st
	end

	function Utils.MultiSelect_Clear(contextKey)
		return Utils.MultiSelect_Init(contextKey)
	end

	-- Toggle selection.
	-- isMulti=false  -> clear + select single (optional: click-again to deselect when allowDeselect=true)
	-- isMulti=true   -> toggle selection for the given id
	-- Returns: actionString, selectedCount
	function Utils.MultiSelect_Toggle(contextKey, id, isMulti, allowDeselect)
		local st, key = _ensure(contextKey)
		local k = _msKey(id)
		if k == nil then return nil, st.count or 0 end

		local before = st.count or 0
		local action

		local allow = false
		if allowDeselect == true then
			allow = true
		elseif type(allowDeselect) == "table" and allowDeselect.allowDeselect == true then
			allow = true
		end

		if isMulti then
			if st.set[k] then
				st.set[k] = nil
				st.count = before - 1
				action = "TOGGLE_OFF"
			else
				st.set[k] = true
				st.count = before + 1
				action = "TOGGLE_ON"
			end
		else
			-- OS-like single selection:
			--   - clear + select single by default
			--   - optionally allow "click again to deselect" when this is the only selected row
			local already = (st.set[k] == true)
			if allow and already and before == 1 then
				st.set = {}
				st.count = 0
				action = "SINGLE_DESELECT"
			else
				st.set = {}
				st.set[k] = true
				st.count = 1
				action = "SINGLE_CLEAR+SELECT"
			end
		end

		st.ver = (st.ver or 0) + 1

		_dbg(("[LoggerSelect] toggle ctx=%s id=%s multi=%s action=%s count %d->%d ver=%d"):format(
			tostring(key), tostring(id), isMulti and "1" or "0", tostring(action), before, st.count or 0, st.ver
		))

		return action, st.count or 0
	end

	-- Set or clear the range-anchor for SHIFT range selection.
	-- The anchor is the last non-shift click target for the given context.
	function Utils.MultiSelect_SetAnchor(contextKey, id)
		local st, key = _ensure(contextKey)
		local before = st.anchor
		local k = _msKey(id)
		st.anchor = k
		-- Anchor changes do not affect highlight rendering directly, so we do not bump st.ver here.
		local ver = st.ver or 0
		_dbg(("[LoggerSelect] anchor ctx=%s from=%s to=%s ver=%d"):format(
			tostring(key), tostring(before), tostring(st.anchor), ver
		))
		return st.anchor
	end

	function Utils.MultiSelect_GetAnchor(contextKey)
		local st = MS[contextKey or "_default"]
		return st and st.anchor or nil
	end

	local function _idOf(x)
		if type(x) == "table" then
			return x.id
		end
		return x
	end

	local function _findIndex(ordered, key)
		if not ordered or not key then return nil end
		for i = 1, #ordered do
			local id = _idOf(ordered[i])
			if _msKey(id) == key then
				return i
			end
		end
		return nil
	end

	-- SHIFT range selection helper.
	-- ordered: array of ids OR array of items with .id (e.g. controller.data)
	-- id: clicked id
	-- isAdd: when true (CTRL+SHIFT) add the range to the existing selection; otherwise replace selection with the range
	-- Returns: actionString, selectedCount
	function Utils.MultiSelect_Range(contextKey, ordered, id, isAdd)
		local st, key = _ensure(contextKey)
		local k = _msKey(id)
		if k == nil then return nil, st.count or 0 end

		local before = st.count or 0
		local action

		local aKey = st.anchor
		local ai = _findIndex(ordered, aKey)
		local bi = _findIndex(ordered, k)

		if not ai or not bi then
			-- If we cannot resolve indices (missing anchor or id), behave like a single select.
			st.set = {}
			st.set[k] = true
			st.count = 1
			if not st.anchor then st.anchor = k end
			action = st.anchor == k and "RANGE_NOANCHOR_SINGLE" or "RANGE_FALLBACK_SINGLE"
		else
			if not isAdd then
				st.set = {}
				st.count = 0
			end
			local from = ai
			local to = bi
			if from > to then
				from, to = to, from
			end

			for i = from, to do
				local id2 = _idOf(ordered[i])
				local k2 = _msKey(id2)
				if k2 ~= nil and not st.set[k2] then
					st.set[k2] = true
					st.count = (st.count or 0) + 1
				end
			end
			action = isAdd and "RANGE_ADD" or "RANGE_SET"
		end

		st.ver = (st.ver or 0) + 1
		_dbg(("[LoggerSelect] range ctx=%s id=%s add=%s action=%s count %d->%d ver=%d anchor=%s"):format(
			tostring(key), tostring(id), isAdd and "1" or "0", tostring(action), before, st.count or 0, st.ver,
			tostring(st.anchor)
		))
		return action, st.count or 0
	end

	function Utils.MultiSelect_IsSelected(contextKey, id)
		local st = MS[contextKey or "_default"]
		if not st or not st.set then return false end
		local k = _msKey(id)
		return (k ~= nil) and (st.set[k] == true) or false
	end

	function Utils.MultiSelect_Count(contextKey)
		local st = MS[contextKey or "_default"]
		return (st and st.count) or 0
	end

	function Utils.MultiSelect_GetVersion(contextKey)
		local st = MS[contextKey or "_default"]
		return (st and st.ver) or 0
	end

	function Utils.MultiSelect_GetSelected(contextKey)
		local st = MS[contextKey or "_default"]
		local out = {}
		if not st or not st.set then return out end
		local n = 0
		for id, v in pairs(st.set) do
			if v then
				n = n + 1
				out[n] = id
			end
		end
		-- Stable ordering for UI/debug; safe even if mixed types.
		table.sort(out, function(a, b)
			local na, nb = tonumber(a), tonumber(b)
			if na and nb then return na < nb end
			return tostring(a) < tostring(b)
		end)
		return out
	end
end


-- Set frame text based on condition:
function Utils.setText(frame, str1, str2, cond)
	if cond then
		frame:SetText(str1)
	else
		frame:SetText(str2)
	end
end

-- =========== Throttles  =========== --

-- Throttle frame OnUpdate:
function Utils.throttle(frame, name, period, elapsed)
	local t = frame[name] or 0
	t = t + elapsed
	if t > period then
		frame[name] = 0
		return true
	end
	frame[name] = t
	return false
end

function Utils.throttledUIUpdate(frame, frameName, period, elapsed, fn)
	if not frameName or type(fn) ~= "function" then
		return false
	end
	if Utils.throttle(frame, frameName, period, elapsed) then
		fn()
		return true
	end
	return false
end

-- =========== Chat + comms helpers  =========== --

-- Convert seconds to readable clock string:
function Utils.sec2clock(seconds)
	local sec = tonumber(seconds)
	if sec <= 0 then
		return "00:00:00"
	end
	-- Compute hours, minutes and seconds properly based on total seconds.
	-- Use the cached floor function to avoid extra allocations in hot paths.
	local total = floor(sec)
	local hours = floor(total / 3600)
	local minutes = floor((total % 3600) / 60)
	local secondsPart = floor(total % 60)
	return format("%02d:%02d:%02d", hours, minutes, secondsPart)
end

-- Sends an addOn message to the appropriate channel:
function Utils.sync(prefix, msg)
	local zone = select(2, IsInInstance())
	if zone == "pvp" or zone == "arena" then
		SendAddonMessage(prefix, msg, "BATTLEGROUND")
	elseif GetRealNumRaidMembers() > 0 then
		SendAddonMessage(prefix, msg, "RAID")
	elseif GetRealNumPartyMembers() > 0 then
		SendAddonMessage(prefix, msg, "PARTY")
	end
end

-- Send messages into chat
function Utils.chat(msg, channel, language, target, bypass)
	if not msg then return end
	SendChatMessage(tostring(msg), channel, language, target)
end

-- Send a whisper to a player by his/her character name
-- Returns true if the message was sent, nil otherwise
function Utils.whisper(target, msg)
	if type(target) == "string" and msg then
		SendChatMessage(msg, "WHISPER", nil, target)
		return true
	end
end

-- =========== Time helpers  =========== --

-- Determines if the player is in a raid instance
function Utils.isRaidInstance()
	local inInstance, instanceType = IsInInstance()
	return ((inInstance) and (instanceType == "raid"))
end

-- Returns the raid difficulty:
function Utils.getDifficulty()
	local difficulty = nil
	local inInstance, instanceType = IsInInstance()
	if inInstance and instanceType == "raid" then
		difficulty = GetRaidDifficulty()
	end
	return difficulty
end

-- Returns the current time:
function Utils.getCurrentTime(server)
	if server == nil then server = true end
	local t = time()
	if server == true then
		local _, month, day, year = CalendarGetDate()
		local hour, minute = GetGameTime()
		t = time({ year = year, month = month, day = day, hour = hour, min = minute })
	end
	return t
end

-- Returns the server offset:
function Utils.getServerOffset()
	local sH, sM = GetGameTime()
	local lH, lM = tonumber(date("%H")), tonumber(date("%M"))
	local sT = sH + sM / 60
	local lT = lH + lM / 60
	local offset = addon.Round((sT - lT) / 0.5) * 0.5
	if offset >= 12 then
		offset = offset - 24
	elseif offset < -12 then
		offset = offset + 24
	end
	return offset
end

-- =========== Base64 encode/decode  =========== --

--[==[ Base64 encode/decode ]==] --
do
	-- Characters table string:
	local char, byte = string.char, string.byte
	local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

	-- Encoding:
	function Utils.encode(data)
		return ((gsub(data, ".", function(x)
			local r, b = "", byte(x)
			for i = 8, 1, -1 do
				r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
			end
			return r
		end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
			if #x < 6 then return "" end
			local c = 0
			for i = 1, 6 do
				c = c + (strsub(x, i, i) == "1" and 2 ^ (6 - i) or 0)
			end
			return strsub(b, c + 1, c + 1)
		end) .. ({ "", "==", "=" })[#data % 3 + 1])
	end

	-- Decoding:
	function Utils.decode(data)
		data = gsub(data, "[^" .. b .. "=]", "")
		return (gsub(data, ".", function(x)
			if x == "=" then return "" end
			local r, f = "", (find(b, x) - 1)
			for i = 6, 1, -1 do
				r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
			end
			return r
		end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
			if #x ~= 8 then return "" end
			local c = 0
			for i = 1, 8 do
				c = c + (strsub(x, i, i) == "1" and 2 ^ (8 - i) or 0)
			end
			return char(c)
		end))
	end
end
