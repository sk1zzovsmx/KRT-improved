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

-- =========== Raid/state helpers  =========== --

-- Resolve a raid table and raid number.
--
-- Returns:
--   raidTableOrNil, resolvedRaidNumOrNil
--
-- Notes:
-- - Uses current raid (KRT_CurrentRaid) when raidNum is nil.
-- - Safe when KRT_Raids is nil.
function Utils.getRaid(raidNum)
	raidNum = raidNum or KRT_CurrentRaid
	if not raidNum then return nil, nil end
	local raids = KRT_Raids
	local raid = raids and raids[raidNum] or nil
	return raid, raidNum
end

-- Backwards-friendly alias (some callers prefer PascalCase).
Utils.GetRaid = Utils.getRaid

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

-- Enable basic drag-to-move behavior on a frame.
--
-- Intentionally kept in Lua (not XML) so window behavior is standardized
-- without embedding logic into Templates.xml.
function Utils.enableDrag(frame, dragButton)
	if not frame or not frame.RegisterForDrag then return end
	-- Ensure the frame is draggable even if XML didn't set these.
	if frame.SetMovable then frame:SetMovable(true) end
	if frame.EnableMouse then frame:EnableMouse(true) end
	if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end

	-- Provide default drag handlers in Lua so Templates.xml stays layout-only.
	--
	-- IMPORTANT: do NOT override custom drag scripts (some frames intentionally
	-- move their parent). Only set handlers when none exist.
	if frame.GetScript and frame.SetScript then
		if not frame:GetScript("OnDragStart") then
			frame:SetScript("OnDragStart", function(self)
				if self.StartMoving then
					self:StartMoving()
				end
			end)
		end
		if not frame:GetScript("OnDragStop") then
			frame:SetScript("OnDragStop", function(self)
				if self.StopMovingOrSizing then
					self:StopMovingOrSizing()
				end
			end)
		end
	end

	frame:RegisterForDrag(dragButton or "LeftButton")
end

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
    -- Legacy alias kept for incremental migrations.
    -- All lists now use the Hybrid implementation to avoid duplicated scroll logic.
    return Utils.makeHybridListController(cfg)
end


-- =========== Hybrid list binding helpers (WotLK 3.3.5a)  =========== --
-- These helpers allow binding row widgets robustly even when the named regions are nested.
-- They are only used during row creation/binding (small number of buttons), not per-update.

local function _krtIterChildren(frame)
    -- GetChildren returns varargs; pack into a table for iteration.
    if not (frame and frame.GetChildren) then return nil end
    return { frame:GetChildren() }
end

local function _krtIterRegions(frame)
    if not (frame and frame.GetRegions) then return nil end
    return { frame:GetRegions() }
end

-- Depth-first search for a descendant (child frame or region) whose full name matches exactly.
function Utils.findNamedDescendant(root, fullName)
    if not (root and fullName and fullName ~= "") then return nil end
    local function scan(frame)
        local regions = _krtIterRegions(frame)
        if regions then
            for i = 1, #regions do
                local r = regions[i]
                if r and r.GetName and r:GetName() == fullName then
                    return r
                end
            end
        end

        local children = _krtIterChildren(frame)
        if children then
            for i = 1, #children do
                local c = children[i]
                if c then
                    if c.GetName and c:GetName() == fullName then
                        return c
                    end
                    local found = scan(c)
                    if found then return found end
                end
            end
        end
        return nil
    end
    return scan(root)
end

-- Depth-first search for a descendant whose name ends with the given suffix.
-- Useful when the element is nested and you only know the tail (e.g. "IconTexture").
function Utils.findDescendantBySuffix(root, suffix)
    if not (root and suffix and suffix ~= "") then return nil end
    local function endsWith(name)
        return type(name) == "string" and name:endsWith(suffix)
    end

    local function scan(frame)
        local regions = _krtIterRegions(frame)
        if regions then
            for i = 1, #regions do
                local r = regions[i]
                local n = r and r.GetName and r:GetName()
                if n and endsWith(n) then
                    return r
                end
            end
        end

        local children = _krtIterChildren(frame)
        if children then
            for i = 1, #children do
                local c = children[i]
                if c then
                    local n = c.GetName and c:GetName()
                    if n and endsWith(n) then
                        return c
                    end
                    local found = scan(c)
                    if found then return found end
                end
            end
        end
        return nil
    end
    return scan(root)
end

-- Bind named parts on a Hybrid row. Tries exact (rowName..part) first; falls back to suffix search.
function Utils.bindRowParts(row, parts, out)
    if not (row and parts) then return out end
    out = out or {}
    local rowName = row.GetName and row:GetName() or nil
    for i = 1, #parts do
        local key = parts[i]
        if type(key) == "string" then
            local full = rowName and (rowName .. key) or key
            out[key] = _G[full] or Utils.findNamedDescendant(row, full) or Utils.findDescendantBySuffix(row, key)
        end
    end
    row._p = out
    return out
end

-- Clear transient fields for Logger loot rows (Hybrid reuse).
function Utils.clearLoggerLootRow(row)
    if not row then return end
    row._itemId = nil
    row._itemLink = nil
    row._itemName = nil
    row._source = nil
    row._tooltipTitle = nil
    row._tooltipSource = nil
    local ui = row._p
    if ui and ui.ItemIconTexture and ui.ItemIconTexture.SetTexture then
        ui.ItemIconTexture:SetTexture(nil)
    end
end

-- Clear transient fields for Logger attendee rows (Hybrid reuse).
function Utils.clearLoggerAttendeeRow(row)
    if not row then return end
    row._playerName = nil
    local ui = row._p
    if ui then
        if ui.Name and ui.Name.SetText then ui.Name:SetText("") end
        if ui.Name and ui.Name.SetVertexColor then ui.Name:SetVertexColor(1, 1, 1) end
        if ui.Join and ui.Join.SetText then ui.Join:SetText("") end
        if ui.Leave and ui.Leave.SetText then ui.Leave:SetText("") end
    end
end


function Utils.makeHybridListController(cfg)
    local self = {
        frameName = nil,
        data = {},
        _asc = false,
        _sortKey = nil,
        _lastHL = nil,
        _active = false,
        _localized = false,
        _dirty = true,
        _rowHeight = tonumber(cfg.rowHeight) or 20,
        _createdRowCount = 0,
    }

    local defer = CreateFrame("Frame")
    defer:Hide()

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

    local function postUpdate()
        if cfg.postUpdate then
            cfg.postUpdate(self.frameName)
        end
    end

    local function applyHighlight()
        local selectedId = cfg.highlightId and cfg.highlightId() or nil
        local focusId = (cfg.focusId and cfg.focusId()) or selectedId

        local selKey
        if cfg.highlightId then
            selKey = selectedId and ("id:" .. tostring(selectedId)) or "id:nil"
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

        local n = self.frameName
        local sf = n and _G[n .. "ScrollFrame"]
        local buttons = sf and sf.buttons
        if not buttons then return end

        local offset = HybridScrollFrame_GetOffset(sf)
        for i = 1, #buttons do
            local row = buttons[i]
            local dataIndex = offset + i
            local it = self.data[dataIndex]
            if row and it then
                local isSel = false
                if cfg.highlightId then
                    isSel = (selectedId ~= nil and it.id == selectedId)
                elseif cfg.highlightFn then
                    isSel = cfg.highlightFn(it.id, it, dataIndex, row) and true or false
                end

                if Utils and Utils.setRowSelected then
                    Utils.setRowSelected(row, isSel)
                else
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

    local function ensureButtons(sf)
        if not (sf and sf.scrollChild and HybridScrollFrame_Update and HybridScrollFrame_CreateButtons) then
            return false
        end

        -- 1) First creation (Blizzard helper). This resets scroll to 0, which is fine the first time.
        if not sf.buttons then
            HybridScrollFrame_CreateButtons(sf, cfg.rowTmpl, 0, 0)
        end

        local buttons = sf.buttons
        if not (buttons and buttons[1]) then
            return false
        end

        -- Track rowHeight from the real template height (authoritative).
        local h = buttons[1].GetHeight and buttons[1]:GetHeight()
        if h and h > 0 then
            self._rowHeight = h
        end

        -- 2) Resize-safe: if the scroll frame grows, ask Blizzard helper to add missing buttons.
        --    HybridScrollFrame_CreateButtons() resets the scroll bar value to 0, so we preserve it.
        local scrollH = sf.GetHeight and sf:GetHeight() or 0
        local rowH = (self._rowHeight and self._rowHeight > 0) and self._rowHeight or 20
        local wanted = math.ceil(scrollH / rowH) + 1
        if wanted < 1 then wanted = 1 end

        if #buttons < wanted then
            local sb = sf.scrollBar
            local prev = (sb and sb.GetValue) and sb:GetValue() or 0

            -- Prevent re-entrant updates while we rebuild buttons.
            local oldUpdate = sf.update
            sf.update = nil
            HybridScrollFrame_CreateButtons(sf, cfg.rowTmpl, 0, 0)
            sf.update = oldUpdate

            buttons = sf.buttons or buttons
            if sb and sb.GetMinMaxValues and sb.SetValue then
                local minVal, maxVal = sb:GetMinMaxValues()
                if prev < minVal then prev = minVal end
                if prev > maxVal then prev = maxVal end
                sb:SetValue(prev)
            end
        end

        -- 3) Bind row widgets once (Option B: cfg.bindRow). Falls back to cfg._rowParts.
        for i = 1, #buttons do
            local row = buttons[i]
            if row and not row._krtBound then
                if cfg.bindRow then
                    cfg.bindRow(row)
                elseif cfg._rowParts then
                    Utils.bindRowParts(row, cfg._rowParts)
                else
                    row._p = row._p or {}
                end
                row._krtBound = true
            end
        end

        self._createdRowCount = #buttons

        if not sf.update then
            sf.update = function()
                self:Fetch()
            end
        end

        if cfg.debugVirtualization and addon and addon.options and addon.options.debug and addon.debug then
            addon:debug(("[Hybrid:%s] rowsCreated=%d"):format(tostring(cfg.keyName or "?"), self._createdRowCount))
        end

        return true
    end

    local function setActive(active)
        self._active = active
        if self._active then
            ensureLocalized()
            self:Dirty()
            return
        end
        releaseData()
        self._lastHL = nil
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
            if okFetch ~= false then
                self._dirty = false
            end
        else
            self:Fetch()
        end
    end

    defer:SetScript("OnUpdate", function(f)
        f:Hide()
        local ok, err = pcall(runUpdate)
        if not ok and err ~= self._lastErr then
            self._lastErr = err
            addon:error(L.LogLoggerUIError:format(tostring(cfg.keyName or "?"), tostring(err)))
        end
    end)

    function self:OnLoad(frame)
        if not frame then return end
        self.frameName = frame:GetName()

        frame:HookScript("OnShow", function()
            setActive(true)
        end)

        frame:HookScript("OnHide", function()
            setActive(false)
        end)

        if frame:IsShown() then
            setActive(true)
        end
    end

    local function clearRow(row)
        if not row then return end
        row._dataIndex = nil
        row._data = nil
        if cfg.clearRow then
            cfg.clearRow(row)
        end
    end

    function self:Fetch()
        if self._fetching then return end
        self._fetching = true
        local n = self.frameName
        if not n then self._fetching = false; return end

        local sf = _G[n .. "ScrollFrame"]
        if not sf then self._fetching = false; return end

        local scrollH = sf:GetHeight() or 0
        if scrollH < 10 then
            defer:Show()
            self._fetching = false
            return false
        end

        if not ensureButtons(sf) then
            self._fetching = false
            return false
        end

        local buttons = sf.buttons
        if not buttons then
            self._fetching = false
            return false
        end

        local totalCount = #self.data
        local totalHeight = totalCount * self._rowHeight
        -- Blizzard usage (3.3.5a): displayedHeight is the total height of the created buttons.
        local displayedHeight = (#buttons) * self._rowHeight
        HybridScrollFrame_Update(sf, totalHeight, displayedHeight)

        local offset = HybridScrollFrame_GetOffset(sf)
        for i = 1, #buttons do
            local row = buttons[i]
            local dataIndex = offset + i
            local it = self.data[dataIndex]
            if it then
                row:SetID(it.id)
                row._dataIndex = dataIndex
                row._data = it
                cfg.drawRow(row, it, dataIndex)
                row:Show()
            else
                row:Hide()
                clearRow(row)
            end
        end

        if cfg.debugVirtualization and addon and addon.options and addon.options.debug and addon.debug then
            addon:debug(("[Hybrid:%s] total=%d visible=%d created=%d offset=%d"):format(
                tostring(cfg.keyName or "?"),
                totalCount,
                #buttons,
                self._createdRowCount,
                offset
            ))
        end

        self._lastHL = nil
        applyHighlight()
        postUpdate()

        self._fetching = false
    end

    function self:Sort(key)
        local cmp = cfg.sorters and cfg.sorters[key]
        if not cmp or #self.data <= 1 then return end
        if self._sortKey ~= key then
            self._sortKey = key
            self._asc = false
        end
        self._asc = not self._asc
        table.sort(self.data, function(a, b) return cmp(a, b, self._asc) end)
        self:Fetch()
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

-- =========== Coalesced refresh helpers (event-driven UI)  =========== --

-- Creates a refresh requester that coalesces multiple triggers into a single UI update.
-- Notes:
--  - Uses a dedicated driver frame (does NOT touch the target frame's OnUpdate).
--  - If called while the target frame is hidden, marks it dirty and refreshes on next OnShow.
--  - WoW 3.3.5a compatible (no C_Timer).
function Utils.makeEventDrivenRefresher(targetOrGetter, updateFn)
	if type(updateFn) ~= "function" then
		error("Utils.makeEventDrivenRefresher: updateFn must be a function")
	end

	local driver = CreateFrame("Frame")
	local pending = false
	local dirtyWhileHidden = false
	local hookedFrame = nil

	local function resolveTarget()
		if type(targetOrGetter) == "function" then
			return targetOrGetter()
		end
		return targetOrGetter
	end

	local function ensureHook(target)
		if not target or not target.HookScript then return end
		if hookedFrame == target then return end
		hookedFrame = target
		target:HookScript("OnShow", function()
			if dirtyWhileHidden then
				dirtyWhileHidden = false
				updateFn()
			end
		end)
	end

	local function run()
		driver:SetScript("OnUpdate", nil)
		pending = false

		local target = resolveTarget()
		if not target or not target.IsShown or not target:IsShown() then
			dirtyWhileHidden = true
			if target then ensureHook(target) end
			return
		end
		updateFn()
	end

	return function()
		local target = resolveTarget()
		if not target then return end
		ensureHook(target)

		if not target:IsShown() then
			dirtyWhileHidden = true
			return
		end

		if pending then return end
		pending = true
		driver:SetScript("OnUpdate", run)
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
	local function msKey(id)
		if id == nil then return nil end
		local n = tonumber(id)
		return n or id
	end

	local function ensureContext(contextKey)
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

	local function debugLog(msg)
		if addon and addon.options and addon.options.debug and addon.debug then
			addon:debug(msg)
		end
	end

	function Utils.multiSelectInit(contextKey)
		local st, key = ensureContext(contextKey)
		st.set = {}
		st.count = 0
		st.ver = (st.ver or 0) + 1
		debugLog(("[LoggerSelect] init ctx=%s ver=%d"):format(tostring(key), st.ver))
		return st
	end

	function Utils.multiSelectClear(contextKey)
		return Utils.multiSelectInit(contextKey)
	end

	-- Toggle selection.
	-- isMulti=false  -> clear + select single (optional: click-again to deselect when allowDeselect=true)
	-- isMulti=true   -> toggle selection for the given id
	-- Returns: actionString, selectedCount
	function Utils.multiSelectToggle(contextKey, id, isMulti, allowDeselect)
		local st, key = ensureContext(contextKey)
		local k = msKey(id)
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

		debugLog(("[LoggerSelect] toggle ctx=%s id=%s multi=%s action=%s count %d->%d ver=%d"):format(
			tostring(key), tostring(id), isMulti and "1" or "0", tostring(action), before, st.count or 0, st.ver
		))

		return action, st.count or 0
	end

	-- Set or clear the range-anchor for SHIFT range selection.
	-- The anchor is the last non-shift click target for the given context.
	function Utils.multiSelectSetAnchor(contextKey, id)
		local st, key = ensureContext(contextKey)
		local before = st.anchor
		local k = msKey(id)
		st.anchor = k
		-- Anchor changes do not affect highlight rendering directly, so we do not bump st.ver here.
		local ver = st.ver or 0
		debugLog(("[LoggerSelect] anchor ctx=%s from=%s to=%s ver=%d"):format(
			tostring(key), tostring(before), tostring(st.anchor), ver
		))
		return st.anchor
	end

	function Utils.multiSelectGetAnchor(contextKey)
		local st = MS[contextKey or "_default"]
		return st and st.anchor or nil
	end

	local function idOf(x)
		if type(x) == "table" then
			return x.id
		end
		return x
	end

	local function findIndex(ordered, key)
		if not ordered or not key then return nil end
		for i = 1, #ordered do
			local id = idOf(ordered[i])
			if msKey(id) == key then
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
	function Utils.multiSelectRange(contextKey, ordered, id, isAdd)
		local st, key = ensureContext(contextKey)
		local k = msKey(id)
		if k == nil then return nil, st.count or 0 end

		local before = st.count or 0
		local action

		local aKey = st.anchor
		local ai = findIndex(ordered, aKey)
		local bi = findIndex(ordered, k)

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
				local id2 = idOf(ordered[i])
				local k2 = msKey(id2)
				if k2 ~= nil and not st.set[k2] then
					st.set[k2] = true
					st.count = (st.count or 0) + 1
				end
			end
			action = isAdd and "RANGE_ADD" or "RANGE_SET"
		end

		st.ver = (st.ver or 0) + 1
		debugLog(("[LoggerSelect] range ctx=%s id=%s add=%s action=%s count %d->%d ver=%d anchor=%s"):format(
			tostring(key), tostring(id), isAdd and "1" or "0", tostring(action), before, st.count or 0, st.ver,
			tostring(st.anchor)
		))
		return action, st.count or 0
	end

	function Utils.multiSelectIsSelected(contextKey, id)
		local st = MS[contextKey or "_default"]
		if not st or not st.set then return false end
		local k = msKey(id)
		return (k ~= nil) and (st.set[k] == true) or false
	end

	function Utils.multiSelectCount(contextKey)
		local st = MS[contextKey or "_default"]
		return (st and st.count) or 0
	end

	function Utils.multiSelectGetVersion(contextKey)
		local st = MS[contextKey or "_default"]
		return (st and st.ver) or 0
	end

	function Utils.multiSelectGetSelected(contextKey)
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

	-- Backward-compatible aliases for legacy call sites.
	Utils.MultiSelect_Init = Utils.multiSelectInit
	Utils.MultiSelect_Clear = Utils.multiSelectClear
	Utils.MultiSelect_Toggle = Utils.multiSelectToggle
	Utils.MultiSelect_SetAnchor = Utils.multiSelectSetAnchor
	Utils.MultiSelect_GetAnchor = Utils.multiSelectGetAnchor
	Utils.MultiSelect_Range = Utils.multiSelectRange
	Utils.MultiSelect_IsSelected = Utils.multiSelectIsSelected
	Utils.MultiSelect_Count = Utils.multiSelectCount
	Utils.MultiSelect_GetVersion = Utils.multiSelectGetVersion
	Utils.MultiSelect_GetSelected = Utils.multiSelectGetSelected
end


-- Set frame text based on condition:
function Utils.setText(frame, str1, str2, cond)
	if cond then
		frame:SetText(str1)
	else
		frame:SetText(str2)
	end
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
