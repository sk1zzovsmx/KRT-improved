local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("KRT")
if not addon then return end

-- ==================== Chat Output Helpers ==================== --
do
	-- Output strings:
	local output          = "|cfff58cba%s|r: %s"
	local chatPrefix      = "Kader Raid Tools"
	local chatPrefixShort = "KRT"

	-- Default function that handles final output:
	local function PreparePrint(text, prefix)
		prefix = prefix or chatPrefixShort
		return format(output, prefix, tostring(text))
	end

	-- Default print function:
	function addon:Print(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "Print: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print(msg)
	end

	-- Print Green Success Message:
	function addon:PrintSuccess(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintSuccess: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_green(msg)
	end

	-- Print Red Error Message:
	function addon:PrintError(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintError: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_red(msg)
	end

	-- Print Orange Warning Message:
	function addon:PrintWarning(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintWarning: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_orange(msg)
	end

	-- Print Blue Info Message:
	function addon:PrintInfo(text, prefix)
		local msg = PreparePrint(text, prefix)
		addon:Debug("DEBUG", "PrintInfo: [%s] %s", tostring(prefix or chatPrefixShort), tostring(text))
		return Utils.print_blue(msg)
	end

	-- Function used for various announcements:
	function addon:Announce(text, channel)
		local originalChannel = channel
		if not channel then
			channel = "SAY"
			-- Switch to party mode if we're in a party:
			if self:IsInParty() then
				channel = "PARTY"		
			-- Switch to raid channel if we're in a raid:
			elseif self:IsInRaid() then
				-- Check for countdown messages
				local countdownTicPattern = L.ChatCountdownTic:gsub("%%d", "%%d+")
				local isCountdownMessage = text:find(countdownTicPattern) or text:find(L.ChatCountdownEnd)

				if isCountdownMessage then
					-- If it's a countdown message:
					if addon.options.countdownSimpleRaidMsg then
						channel = "RAID" -- Force RAID if countdownSimpleRaidMsg is true
					-- Use RAID_WARNING if leader/officer AND useRaidWarning is true
					elseif addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
						channel = "RAID_WARNING"
					else
						channel = "RAID" -- Fallback to RAID
					end
				else
					if addon.options.useRaidWarning and (IsRaidLeader() or IsRaidOfficer()) then
						channel = "RAID_WARNING"
					else
						channel = "RAID" -- Fallback to RAID
					end
				end
			end
		end
		-- Let's Go!
		SendChatMessage(tostring(text), channel)
	end
end

