local addonName, addon     = ...
addon.Utils                = addon.Utils or {}

local Utils                = addon.Utils
local L                    = addon.L

local type, ipairs, pairs  = type, ipairs, pairs
local floor, random        = math.floor, math.random
local setmetatable         = setmetatable
local getmetatable         = getmetatable
local tinsert, tremove     = table.insert, table.remove
local find, match          = string.find, string.match
local format, gsub         = string.format, string.gsub
local strsub, strlen       = string.sub, string.len
local lower, upper         = string.lower, string.upper
local ucfirst             = _G.string and _G.string.ucfirst
local select, unpack       = select, unpack
local LibStub              = LibStub

local GetLocale            = GetLocale
local GetTime              = GetTime
local GetRaidRosterInfo    = GetRaidRosterInfo
local GetRealmName         = GetRealmName
local GetAchievementLink   = GetAchievementLink
local UnitClass            = UnitClass
local UnitInRaid           = UnitInRaid
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader    = UnitIsGroupLeader
local UnitIsPartyLeader    = UnitIsPartyLeader
local UnitIsRaidLeader     = UnitIsRaidLeader
local UnitIsRaidOfficer    = UnitIsRaidOfficer
local UnitLevel            = UnitLevel
local UnitName             = UnitName

local ITEM_LINK_FORMAT     = "|c%s|Hitem:%d:%s|h[%s]|h|r"

function Utils.applyDebugSetting(enabled)
	if addon and addon.options then
		addon.options.debug = enabled and true or false
	end
	local levels = addon and addon.Logger and addon.Logger.logLevels or {}
	local level = enabled and levels.DEBUG or (KRT_Debug and KRT_Debug.level)
	if addon and addon.SetLogLevel and level then
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

---============================================================================
-- Small helpers / iteration
---============================================================================

-- Group/pet iteration in one call
function Utils.forEachGroupUnit(cb, includePets)
	local iter, state, index = addon.UnitIterator(not includePets and true or nil)
	for unit, owner in iter, state, index do
		cb(unit, owner)
	end
end

---============================================================================
-- String helpers
---============================================================================

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
	return (ucfirst and ucfirst(text)) or text
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

---============================================================================
-- Roster helpers
---============================================================================

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

function Utils.getRaidRosterData(unit)
	local index = UnitInRaid(unit)

	local rank, subgroup, level, classL, class
	if index then
		_, rank, subgroup, level, classL, class = GetRaidRosterInfo(index)
	end

	rank = Utils.getUnitRank(unit, rank)
	subgroup = subgroup or 1
	level = level or UnitLevel(unit)

	if not classL or not class then
		classL = classL or select(1, UnitClass(unit))
		class = class or select(2, UnitClass(unit))
	end

	return rank, subgroup, level, classL, class
end

---============================================================================
-- Lightweight throttles
---============================================================================

-- Lightweight throttle (keyed)
do
	local last = {}

	function Utils.throttleKey(key, sec)
		local now = GetTime()
		sec = sec or 1
		if not last[key] or (now - last[key]) >= sec then
			last[key] = now
			return true
		end
	end
end

---============================================================================
-- Callback utilities
---============================================================================

do
	local callbacks = {}

	function Utils.registerCallback(e, func)
		if not e or type(func) ~= "function" then
			error(L.StrCbErrUsage)
		end
		callbacks[e] = callbacks[e] or {}
		tinsert(callbacks[e], func)
		return #callbacks
	end

	function Utils.triggerEvent(e, ...)
		if not callbacks[e] then return end
		for i, v in ipairs(callbacks[e]) do
			local ok, err = pcall(v, e, ...)
			if not ok then
				addon:error(L.StrCbErrExec:format(tostring(v), tostring(e), err))
			end
		end
	end
end

---============================================================================
-- Frame helpers
---============================================================================

function Utils.getFrameName()
	return addon.UIMaster:GetName()
end

function Utils.makeConfirmPopup(key, text, onAccept, cancels)
	StaticPopupDialogs[key] = {
		text         = text,
		button1      = OKAY,
		button2      = CANCEL,
		OnAccept     = onAccept,
		cancels      = cancels or key,
		timeout      = 0,
		whileDead    = 1,
		hideOnEscape = 1,
	}
end

function Utils.makeEditBoxPopup(key, text, onAccept, onShow)
	StaticPopupDialogs[key] = {
		text         = text,
		button1      = SAVE,
		button2      = CANCEL,
		timeout      = 0,
		whileDead    = 1,
		hideOnEscape = 1,
		hasEditBox   = 1,
		cancels      = key,
		OnShow       = function(self)
			if onShow then
				onShow(self)
			end
		end,
		OnHide       = function(self)
			self.editBox:SetText("")
			self.editBox:ClearFocus()
		end,
		OnAccept     = function(self)
			onAccept(self, self.editBox:GetText())
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

---============================================================================
-- Tooltip helpers
---============================================================================

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

---============================================================================
-- Global convenience helpers (kept as-is)
---============================================================================

-- Shuffle a table:
_G.table.shuffle = function(t)
	local n = #t
	while n > 2 do
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
	return #str >= #piece and find(str, #str - #piece + 1, true) and true or false
end

-- Uppercase first:
_G.string.ucfirst = function(str)
	str = lower(str)
	return gsub(str, "%a", upper, 1)
end

---============================================================================
-- Color utilities
---============================================================================

function Utils.rgbToHex(r, g, b)
	if r and g and b and r <= 1 and g <= 1 and b <= 1 then
		r, g, b = r * 255, g * 255, b * 255
	end
	return addon.RGBToHex(r, g, b)
end

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
	local c = addon.Compat.GetClassColorObj(className)
	return (c and c.r or 1), (c and c.g or 1), (c and c.b or 1)
end

---============================================================================
-- Generic utilities
---============================================================================

-- Determines if a given string is a number
function Utils.isNumber(str)
	local valid = false
	if str then
		valid = find(str, "^(%d+%.?%d*)$")
	end
	return valid
end

-- Determines if the given string is non-empty:
function Utils.isString(str)
	return (str and strlen(str) > 0)
end

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

-- Lock/Unlock Highlight:
function Utils.toggleHighlight(frame, cond)
	if cond then
		frame:LockHighlight()
	else
		frame:UnlockHighlight()
	end
end

-- Set frameent text with condition:
function Utils.setText(frame, str1, str2, cond)
	if cond then
		frame:SetText(str1)
	else
		frame:SetText(str2)
	end
end

-- Return with IF:
function Utils.returnIf(cond, a, b)
	return cond and a or b
end

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

-- Boolean <> String conversion:
function Utils.bool2str(bool)
	return bool and "true" or "false"
end

function Utils.str2bool(str)
	return (str ~= "false")
end

-- Number <> Boolean conversion:
function Utils.bool2num(bool)
	return bool and 1 or 0
end

function Utils.num2bool(num)
	return (num ~= 0)
end

-- Convert seconds to readable clock string:
function Utils.sec2clock(seconds)
	local sec = tonumber(seconds)
	if sec <= 0 then
		return "00:00:00"
	end
	local h = floor(sec, 3600)
	local m = floor(sec - h, 60)
	local s = floor(sec - h - m)
	return format("%02d:%02d:%02d", h / 3600, m / 60, s)
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

do
	local lastChat = 0

	function Utils.chat(msg, channel, language, target, bypass)
		if not msg then return end
		if not bypass then
			local throttle = addon.options and addon.options.chatThrottle or 0
			local now = GetTime()
			if throttle > 0 and (now - lastChat) < throttle then return end
			lastChat = now
		end
		SendChatMessage(tostring(msg), channel, language, target)
	end
end

-- Send a whisper to a player by his/her character name
-- Returns true if the message was sent, nil otherwise
function Utils.whisper(target, msg)
	if type(target) == "string" and msg then
		SendChatMessage(msg, "WHISPER", nil, target)
		return true
	end
end

-- Returns the current UTC date and time in seconds:
function Utils.getUTCTimestamp()
	local utcDateTime = date("!*t")
	return time(utcDateTime)
end

function Utils.getSecondsAsString(t)
	return Utils.sec2clock(t)
end

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
	server = server or true
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

---============================================================================
-- List controller helpers
---============================================================================

do
	local _G          = _G
	local CreateFrame = CreateFrame

	local wipe        = _G.wipe or table.wipe
	local tinsert     = _G.tinsert
	local ipairs      = _G.ipairs
	local pairs       = _G.pairs
	local format      = _G.format
	local date        = _G.date
	local math_max    = math.max

	function Utils.makeListController(cfg)
		local self = {
			frameName  = nil,
			data       = {},
			_rows      = {},
			_rowByName = {},
			_asc       = false,
			_lastHL    = nil,
			_active    = true,
			_localized = false,
			_lastWidth = nil,
			_dirty     = true,
		}

		local defer = CreateFrame("Frame")
		defer:Hide()

		local function acquireRow(btnName, parent, tmpl)
			local row = self._rowByName[btnName]
			if row then
				row:Show()
				return row
			end

			row = CreateFrame("Button", btnName, parent, tmpl)
			self._rowByName[btnName] = row

			if cfg._rowParts and not row._p then
				local p = {}
				for i = 1, #cfg._rowParts do
					local part = cfg._rowParts[i]
					p[part] = _G[btnName .. part]
				end
				row._p = p
			end

			return row
		end

		local function hideExtraRows(fromIndex)
			for i = fromIndex, #self._rows do
				local r = self._rows[i]
				if r then r:Hide() end
			end
		end

		local function applyHighlightAndPost()
			if cfg.highlightId then
				local sel = cfg.highlightId()
				if sel ~= self._lastHL then
					self._lastHL = sel
					for i = 1, #self.data do
						local it  = self.data[i]
						local row = self._rows[i]
						if row then
							Utils.toggleHighlight(row, sel ~= nil and it.id == sel)
						end
					end
				end
			end
			if cfg.postUpdate then cfg.postUpdate(self.frameName) end
		end

		function self:Touch()
			defer:Show()
		end

		function self:Dirty()
			self._dirty = true
			defer:Show()
		end

		defer:SetScript("OnUpdate", function(f)
			f:Hide()
			if not self._active or not self.frameName then return end

			if self._dirty then
				local tableFree = addon.Table and addon.Table.free
				if cfg.poolTag and tableFree then
					for i = 1, #self.data do
						tableFree(cfg.poolTag, self.data[i])
					end
				end

				wipe(self.data)
				if cfg.getData then cfg.getData(self.data) end

				self:Fetch()
				self._dirty = false
			end

			applyHighlightAndPost()
		end)

		function self:OnLoad(frame)
			if not frame then return end
			self.frameName = frame:GetName()

			frame:SetScript("OnShow", function()
				self._active = true
				if not self._localized and cfg.localize then
					cfg.localize(self.frameName)
					self._localized = true
				end
				self:Dirty()
			end)

			frame:SetScript("OnHide", function()
				self._active = false
			end)

			if frame:IsShown() then
				self._active = true
				if not self._localized and cfg.localize then
					cfg.localize(self.frameName)
					self._localized = true
				end
				self:Dirty()
			end
		end

		function self:Fetch()
			local n = self.frameName
			if not n then return end

			local sf = _G[n .. "ScrollFrame"]
			local sc = _G[n .. "ScrollFrameScrollChild"]
			if not (sf and sc) then return end

			local scrollW = sf:GetWidth() or 0
			local widthChanged = (self._lastWidth ~= scrollW)
			self._lastWidth = scrollW

			local totalH = 0
			local count = #self.data

			for i = 1, count do
				local it      = self.data[i]
				local btnName = cfg.rowName(n, it, i)

				local row     = self._rows[i]
				if not row or row:GetName() ~= btnName then
					row = acquireRow(btnName, sc, cfg.rowTmpl)
					self._rows[i] = row
				end

				row:SetID(it.id)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 0, -totalH)
				if widthChanged then row:SetWidth(scrollW - 20) end

				local rH = cfg.drawRow(row, it)
				local usedH = rH or row:GetHeight() or 20
				totalH = totalH + usedH

				row:Show()
			end

			hideExtraRows(count + 1)
			sc:SetHeight(math_max(totalH, sf:GetHeight()))

			self._lastHL = nil
		end

		function self:Sort(key)
			local cmp = cfg.sorters and cfg.sorters[key]
			if not cmp or #self.data <= 1 then return end
			self._asc = not self._asc
			table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
			self:Fetch()
			applyHighlightAndPost()
		end

		self._makeConfirmPopup = Utils.makeConfirmPopup

		return self
	end

	function Utils.bindListController(module, controller)
		module.OnLoad = function(_, frame) controller:OnLoad(frame) end
		module.Fetch = function() controller:Fetch() end
		module.Sort = function(_, t) controller:Sort(t) end
	end

	function Utils.registerCallbacks(names, handler)
		for i = 1, #names do
			Utils.registerCallback(names[i], handler)
		end
	end
end

---============================================================================
-- Base64 encode/decode
---============================================================================

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
		data = gsub(data, "[^" .. b .. "=]", '')
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
