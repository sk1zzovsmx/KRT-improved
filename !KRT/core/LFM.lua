local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
if not addon then return end

-- ==================== LFM Spam Frame ==================== --

do
	addon.Spammer = {}
	local Spammer = addon.Spammer

	local spamFrame = CreateFrame("Frame")
	local frameName

	local LocalizeUIFrame
	local localized = false

	local UpdateUIFrame
	local updateInterval = 0.05

	local FindAchievement

	local loaded = false

	local name, tankClass, healerClass, meleeClass, rangedClass
	local duration = 60
	local tank = 0
	local healer = 0
	local melee = 0
	local ranged = 0
	local message, output = nil, "LFM"
	local finalOutput = ""
	local length = 0
	local channels = {}

	local ticking = false
	local paused = false
	local tickStart, tickPos = 0, 0

	local ceil = math.ceil

	-- OnLoad frame:
	function Spammer:OnLoad(frame)
		addon:Debug("DEBUG", "LFM Spam frame loaded.")
		if not frame then return end
		UISpammer = frame
		frameName = frame:GetName()
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnUpdate", UpdateUIFrame)
	end

	-- Toggle frame visibility:
	function Spammer:Toggle()
		addon:Debug("DEBUG", "Toggling LFM Spam frame visibility.")
		Utils.toggle(UISpammer)
	end

	-- Hide frame:
	function Spammer:Hide()
		addon:Debug("DEBUG", "Hiding LFM Spam frame.")
		if UISpammer and UISpammer:IsShown() then
			UISpammer:Hide()
		end
	end

	-- Save edit box:-
	function Spammer:Save(box)
		addon:Debug("DEBUG", "Saving data from edit box.")
		if not box then return end
		local boxName = box:GetName()
		local target = gsub(boxName, frameName, "")
		if find(target, "Chat") then
			KRT_Spammer.Channels = KRT_Spammer.Channels or {}
			local channel = gsub(target, "Chat", "")
			local checked = (box:GetChecked() == 1)
			local existed = Utils.checkEntry(KRT_Spammer.Channels, channel)
			if checked and not existed then
				tinsert(KRT_Spammer.Channels, channel)
			elseif not checked and existed then
				Utils.removeEntry(KRT_Spammer.Channels, channel)
			end
		else
			local value = box:GetText():trim()
			value = (value == "") and nil or value
			KRT_Spammer[target] = value
			box:ClearFocus()
			if ticking and paused then paused = false end
		end
		loaded = false
	end

	-- Start spamming:
	function Spammer:Start()
		addon:Debug("DEBUG", "Starting spam with message: " .. (finalOutput or "nil"))
		if strlen(finalOutput) > 3 and strlen(finalOutput) <= 255 then
			if paused then
				paused = false
			elseif ticking then
				ticking = false
			else
				tickStart = GetTime()
				duration = tonumber(duration)
				tickPos = (duration >= 1 and duration or 60) + 1
				ticking = true
				-- Spammer:Spam()
			end
		end
	end

	-- Stop spamming:
	function Spammer:Stop()
		addon:Debug("DEBUG", "Stopping spam.")
		_G[frameName.."Tick"]:SetText(duration or 0)
		ticking = false
		paused = false
	end

	-- Pausing spammer
	function Spammer:Pause()
		addon:Debug("DEBUG", "Pausing spam.")
		paused = true
	end

	-- Send spam message:
	function Spammer:Spam()
		addon:Debug("DEBUG", "Sending spam message: " .. (finalOutput or "nil"))
		if strlen(finalOutput) > 255 then
			addon:PrintError(L.StrSpammerErrLength)
			ticking = false
			return
		end
		if #channels <= 0 then
			SendChatMessage(tostring(finalOutput), "YELL")
			return
		end
		for i, c in ipairs(channels) do
			if c == "Guild" or c == "Yell" then
				SendChatMessage(tostring(finalOutput), upper(c))
			else
				SendChatMessage(tostring(finalOutput), "CHANNEL", nil, c)
			end
		end
	end

	-- Tab move between edit boxes:
	function Spammer:Tab(a, b)
		addon:Debug("DEBUG", "Tabbing between edit boxes.")
		local target
		if IsShiftKeyDown() and _G[frameName..b] ~= nil then
			target = _G[frameName..b]
		elseif _G[frameName..a] ~= nil then
			target = _G[frameName..a]
		end
		if target then target:SetFocus() end
	end

	-- Clears Data
	function Spammer:Clear()
		addon:Debug("DEBUG", "Clearing all LFM Spam data.")
		for k, _ in pairs(KRT_Spammer) do
			if k ~= "Channels" and k ~= "Duration" then
				KRT_Spammer[k] = nil
			end
		end
		message, output, finalOutput = nil, "LFM", ""
		Spammer:Stop()
		_G[frameName.."Name"]:SetText("")
		_G[frameName.."Tank"]:SetText("")
		_G[frameName.."TankClass"]:SetText("")
		_G[frameName.."Healer"]:SetText("")
		_G[frameName.."HealerClass"]:SetText("")
		_G[frameName.."Melee"]:SetText("")
		_G[frameName.."MeleeClass"]:SetText("")
		_G[frameName.."Ranged"]:SetText("")
		_G[frameName.."RangedClass"]:SetText("")
		_G[frameName.."Message"]:SetText("")
	end

	-- Localizing ui frame:
	function LocalizeUIFrame()
		if localized then return end
		if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
			_G[frameName.."CompStr"]:SetText(L.StrSpammerCompStr)
			_G[frameName.."NeedStr"]:SetText(L.StrSpammerNeedStr)
			_G[frameName.."MessageStr"]:SetText(L.StrSpammerMessageStr)
			_G[frameName.."PreviewStr"]:SetText(L.StrSpammerPreviewStr)
		end
		_G[frameName.."Title"]:SetText(format(titleString, L.StrSpammer))
		_G[frameName.."StartBtn"]:SetScript("OnClick", Spammer.Start)

		local durationBox = _G[frameName.."Duration"]
		durationBox.tooltip_title = AUCTION_DURATION
		addon:SetTooltip(durationBox, L.StrSpammerDurationHelp)

		local messageBox = _G[frameName.."Message"]
		messageBox.tooltip_title = L.StrMessage
		addon:SetTooltip(messageBox, {
			L.StrSpammerMessageHelp1,
			L.StrSpammerMessageHelp2,
			L.StrSpammerMessageHelp3,
		})

		localized = true
	end

	-- OnUpdate frame:
	function UpdateUIFrame(self, elapsed)
		LocalizeUIFrame()
		if Utils.periodic(self, frameName, updateInterval, elapsed) then
			if not loaded then
				for k, v in pairs(KRT_Spammer) do
					if k == "Channels" then
						for i, c in ipairs(v) do
							_G[frameName.."Chat"..c]:SetChecked()
						end
					elseif _G[frameName..k] then
						_G[frameName..k]:SetText(v)
					end
				end
				loaded = true
			end

			-- We build the message only if the frame is shown
			if UISpammer:IsShown() then
				channels = KRT_Spammer.Channels or {}
				name        = _G[frameName.."Name"]:GetText():trim()
				tank        = tonumber(_G[frameName.."Tank"]:GetText()) or 0
				tankClass   = _G[frameName.."TankClass"]:GetText():trim()
				healer      = tonumber(_G[frameName.."Healer"]:GetText()) or 0
				healerClass = _G[frameName.."HealerClass"]:GetText():trim()
				melee       = tonumber(_G[frameName.."Melee"]:GetText()) or 0
				meleeClass  = _G[frameName.."MeleeClass"]:GetText():trim()
				ranged      = tonumber(_G[frameName.."Ranged"]:GetText()) or 0
				rangedClass = _G[frameName.."RangedClass"]:GetText():trim()
				message     = _G[frameName.."Message"]:GetText():trim()

				local temp = output
				if string.trim(name) ~= "" then temp = temp.." "..name end
				if tank > 0 or healer > 0 or melee > 0 or ranged > 0 then
					temp = temp.." - Need"
					if tank > 0 then
						temp = temp..", "..tank.." Tank"
						if tankClass ~= "" then temp = temp.." ("..tankClass..")" end
					end
					if healer > 0 then
						temp = temp..", "..healer.." Healer"
						if healerClass ~= "" then temp = temp.." ("..healerClass..")" end
					end
					if melee > 0 then
						temp = temp..", "..melee.." Melee"
						if meleeClass ~= "" then temp = temp.." ("..meleeClass..")" end
					end
					if ranged > 0 then
						temp = temp..", "..ranged.." Ranged"
						if rangedClass ~= "" then temp = temp.." ("..rangedClass..")" end
					end
				end
				if message ~= "" then
					temp = temp.. " - "..FindAchievement(message)
				end

				if temp ~= "LFM" then
					local total = tank + healer + melee + ranged
					local max = name:find("25") and 25 or 10
					temp = temp .. " ("..max-(total or 0).."/"..max..")"

					_G[frameName.."Output"]:SetText(temp)
					length = strlen(temp)
					_G[frameName.."Length"]:SetText(length.."/255")

					if length <= 0 then
						_G[frameName.."Length"]:SetTextColor(0.5, 0.5, 0.5)
					elseif length <= 255 then
						_G[frameName.."Length"]:SetTextColor(0.0, 1.0, 0.0)
						_G[frameName.."Message"]:SetMaxLetters(255)
					else
						_G[frameName.."Message"]:SetMaxLetters(strlen(message) - 1)
						_G[frameName.."Length"]:SetTextColor(1.0, 0.0, 0.0)
					end
				else
					_G[frameName.."Output"]:SetText(temp)
				end

				-- Set set duration:
				duration = _G[frameName.."Duration"]:GetText()
				if duration == "" then
					duration = 60
					_G[frameName.."Duration"]:SetText(duration)
				end
				finalOutput = temp
				Utils.setText(_G[frameName.."StartBtn"], (paused and L.BtnResume or L.BtnStop), START, ticking == true)
				Utils.enableDisable(_G[frameName.."StartBtn"], (strlen(finalOutput) > 3 and strlen(finalOutput) <= 255))
			end

			if ticking then
				if not paused then
					local count = ceil(duration - GetTime() + tickStart)
					local i = tickPos - 1
					while i >= count do
						_G[frameName.."Tick"]:SetText(i)
						i = i - 1
					end
					tickPos = count
					if tickPos < 0 then tickPos = 0 end
					if tickPos == 0 then
						_G[frameName.."Tick"]:SetText("")
						Spammer:Spam()
						ticking = false
						Spammer:Start()
					end
				end
			end
		end
	end

	function FindAchievement(inp)
		addon:Debug("DEBUG", "Finding achievement in message: " .. (inp or "nil"))
		local out = inp:trim()
		if out and out ~= "" and find(out, "%{%d*%}") then
			local b, e = find(out, "%{%d*%}")
			local id = strsub(out, b+1, e-1)
			if not id or id == "" or not GetAchievementLink(id) then
				link = "["..id.."]"
			else
				link = GetAchievementLink(id)
			end
			out = strsub(out, 0, b-1)..link..strsub(out, e+1)
		end
		return out
	end

	-- To spam even if the frame is closed:
	spamFrame:SetScript("OnUpdate", function(self, elapsed)
		if UISpammer then UpdateUIFrame(UISpammer, elapsed) end
	end)
end

