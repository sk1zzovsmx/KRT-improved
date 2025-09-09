local addonName, addon = ...
addon.Utils = addon.Utils or {}

local Utils   = addon.Utils
local L       = addon.L
local Compat  = addon.Compat

-- Embed LibCompat mixins onto Utils for convenience
if Compat and Compat.Embed then
       Compat:Embed(Utils) -- Utils.After, Utils.UnitIterator, Utils.Table, etc.
end

-- LibCompat aliases
Utils.tCopy     = Compat and Compat.tCopy
Utils.tLength   = Compat and Compat.tLength
Utils.tContains = (Compat and Compat.tContains) or tContains
Utils.tIndexOf  = Compat and Compat.tIndexOf

-- Practical helper aliases
function Utils.after(sec, fn) return Utils.After(sec, fn) end

-- Group/pet iteration in one call
function Utils.forEachGroupUnit(cb, includePets)
       local iter, state, index = Utils.UnitIterator(not includePets and true or nil)
       for unit, owner in iter, state, index do
               cb(unit, owner)
       end
end

local type, ipairs, pairs = type, ipairs, pairs
local floor, random = math.floor, math.random

local function round(number, significance)
	return floor((number / (significance or 1)) + 0.5) * (significance or 1)
end
local setmetatable, getmetatable = setmetatable, getmetatable
local tinsert, tremove = table.insert, table.remove
local find, match = string.find, string.match
local format, gsub = string.format, string.gsub
local strsub, strlen = string.sub, string.len
local lower, upper = string.lower, string.upper
local select, unpack = select, unpack
local GetLocale = GetLocale
local GetTime = GetTime
local tContains = tContains

-- Lightweight throttle (keyed)
local last = {}
function Utils.throttleKey(key, sec)
        local now = GetTime()
        sec = sec or 1
        if not last[key] or (now - last[key]) >= sec then
                last[key] = now
                return true
        end
end

-- ============================================================================
-- Callback utilities
-- ============================================================================

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

-- ============================================================================
-- Frame helpers
-- ============================================================================

function Utils.getFrameName()
        local name
        if addon.UIMaster ~= nil then
                name = addon.UIMaster:GetName()
        end
        return name
end

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

-- ============================================================================
-- Color utilities
-- ============================================================================

function Utils.rgbToHex(r, g, b)
        if r and g and b and r <= 1 and g <= 1 and b <= 1 then
                r, g, b = r * 255, g * 255, b * 255
        end
        if Compat and Compat.RGBToHex then
                return Compat.RGBToHex(r, g, b)
        end
        return format("%02x%02x%02x", r, g, b)
end

function addon.GetClassColor(name)
        name = (name == "DEATH KNIGHT") and "DEATHKNIGHT" or name
        local c = Compat and Compat.GetClassColorObj and Compat.GetClassColorObj(name)
        if not c then
                return 1, 1, 1
        end
        return c.r, c.g, c.b
end

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
	if frame == nil then
		return
	elseif cond and frame:IsEnabled() == 0 then
		frame:Enable()
	elseif not cond and frame:IsEnabled() == 1 then
		frame:Disable()
	end
end

-- Unconditional show/hide frame:
function Utils.toggle(frame)
	if frame == nil then
		return
	elseif frame:IsVisible() then
		frame:Hide()
	else
		frame:Show()
	end
end

-- Conditional Show/Hide Frame:
function Utils.showHide(frame, cond)
        if frame == nil then
                return
        elseif cond and not frame:IsShown() then
                frame:Show()
        elseif not cond and frame:IsShown() then
                frame:Hide()
        end
end

function Utils.createPool(frameType, parent, template, resetter)
        if Compat and Compat.CreateFramePool then
                return Compat.CreateFramePool(frameType, parent, template, resetter)
        end
end

-- Lock/Unlock Highlight:
function Utils.toggleHighlight(frame, cond)
	if frame == nil then
		return
	elseif cond then
		frame:LockHighlight()
	else
		frame:UnlockHighlight()
	end
end

-- Set frameent text with condition:
function Utils.setText(frame, str1, str2, cond)
	if frame == nil then
		return
	elseif cond then
		frame:SetText(str1)
	else
		frame:SetText(str2)
	end
end

-- Return with IF:
function Utils.returnIf(cond, a, b)
	return (cond ~= nil and cond ~= false) and a or b
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

-- Send a whisper to a player by his/her character name or BNet ID
-- Returns true if the message was sent, nil otherwise
function Utils.whisper(target, msg)
	if type(target) == "number" then
		-- Make sure to never send BNet whispers to ourselves.
		if not BNIsSelf(target) then
			BNSendWhisper(target, msg)
			return true
		end
	elseif type(target) == "string" then
		-- Unlike above, it is sometimes useful to whisper ourselves.
		SendChatMessage(msg, "WHISPER", nil, target)
		return true
	end
end

-- local BNSendWhisper = Utils.whisper --

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
        local offset = round(sT - lT, 0.5)
	if offset >= 12 then
		offset = offset - 24
	elseif offset < -12 then
		offset = offset + 24
	end
	return offset
end

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
