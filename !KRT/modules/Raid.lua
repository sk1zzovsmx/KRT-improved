local addonName, addon = ...
addon.Raid = {}
local Raid = addon.Raid

	local inRaid = false
	local numRaid = 0
	local GetLootMethod      = GetLootMethod
	local GetNumPartyMembers = GetNumPartyMembers
	local GetNumRaidMembers  = GetNumRaidMembers
	local GetRaidRosterInfo  = GetRaidRosterInfo

	----------------------
	-- Logger Functions --
	----------------------

	-- Update raid roster:
	function addon:UpdateRaidRoster()
		if not KRT_CurrentRaid then return end
		numRaid = GetNumRaidMembers()
		addon:Debug("DEBUG", "Updating raid roster. Members detected: %d", numRaid)
		if numRaid == 0 then
			addon:Debug("INFO", "Raid disbanded. Ending current raid.")
			Raid:End()
			return
		end
		local realm = GetRealmName() or UNKNOWN
		local players = {}
		for i = 1, numRaid do
			local name, rank, subgroup, level, classL, class, _, online = GetRaidRosterInfo(i)
			if name then
				tinsert(players, name)
				inRaid = false
				for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
					if v.name == name and v.leave == nil then
						inRaid = true
					end
				end
				local unitID = "raid"..tostring(i)
				local raceL, race = UnitRace(unitID)
				if not inRaid then
					addon:Debug("INFO", "New player joined raid: %s", name)
					local toRaid = {
						name = name, rank = rank, subgroup = subgroup,
						class = class or "UNKNOWN", join = Utils.GetCurrentTime(), leave = nil
					}
					Raid:AddPlayer(toRaid)
				end
				if not KRT_Players[realm][name] then
					KRT_Players[realm][name] = {
						name = name, level = level, race = race, raceL = raceL,
						class = class or "UNKNOWN", classL = classL, sex = UnitSex(unitID)
					}
				end
			end
		end
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			local found = nil
			for _, p in ipairs(players) do if v.name == p then found = true break end end
			if not found and v.leave == nil then
				addon:Debug("INFO", "Player left raid: %s", v.name)
				v.leave = Utils.GetCurrentTime()
			end
		end
		Utils.unschedule(addon.UpdateRaidRoster)
	end

	-- Creates a new raid log entry:
	function Raid:Create(zoneName, raidSize)
		if KRT_CurrentRaid then
			addon:Debug("INFO", "Ending previous raid before creating new one.")
			self:End()
		end
		numRaid = GetNumRaidMembers()
		if numRaid == 0 then return end
		local realm = GetRealmName() or UNKNOWN
		local currentTime = Utils.GetCurrentTime()
		addon:Debug("INFO", "Creating new raid: %s (%d-man)", zoneName, raidSize)
		local raidInfo = {
			realm = realm,
			zone = zoneName,
			size = raidSize,
			players = {},
			bossKills = {},
			loot = {},
			startTime = currentTime,
			changes = {},
		}
		for i = 1, numRaid do
			local name, rank, subgroup, level, classL, class = GetRaidRosterInfo(i)
			if name then
				local unitID = "raid"..tostring(i)
				local raceL, race = UnitRace(unitID)
				tinsert(raidInfo.players, {
					name	 = name,
					rank	 = rank,
					subgroup = subgroup,
					class	= class or "UNKNOWN",
					join	 = Utils.GetCurrentTime(),
					leave	= nil,
				})
				KRT_Players[realm][name] = {
					name   = name,
					level  = level,
					race   = race,
					raceL  = raceL,
					class  = class or "UNKNOWN",
					classL = classL,
					sex	= UnitSex(unitID),
				}
			end
		end
		tinsert(KRT_Raids, raidInfo)
		KRT_CurrentRaid = #KRT_Raids
		addon:Debug("INFO", "Raid created with ID: %d", KRT_CurrentRaid)
		TriggerEvent("RaidCreate", KRT_CurrentRaid)
		Utils.schedule(3, addon.UpdateRaidRoster)
	end

	-- Ends the current raid entry:
	function Raid:End()
		if not KRT_CurrentRaid then return end
		addon:Debug("INFO", "Ending raid ID: %d", KRT_CurrentRaid)
		Utils.unschedule(addon.Raid.UpdateRaidRoster)
		local currentTime = Utils.GetCurrentTime()
		for _, v in pairs(KRT_Raids[KRT_CurrentRaid].players) do
			if not v.leave then v.leave = currentTime end
		end
		KRT_Raids[KRT_CurrentRaid].endTime = currentTime
		KRT_CurrentRaid = nil
		KRT_LastBoss	= nil
	end

	-- Checks raid status:
	function Raid:Check(instanceName, instanceDiff)
		if not KRT_CurrentRaid then
			addon:Debug("INFO", "No active raid. Creating new one for instance: %s", instanceName)
			Raid:Create(instanceName, (instanceDiff % 2 == 0 and 25 or 10))
			return
		end

		local current = KRT_Raids[KRT_CurrentRaid]

		if current then
			if current.zone == instanceName then
				local desiredSize = (instanceDiff % 2 == 0) and 25 or 10
				if current.size ~= desiredSize then
					addon:Debug("INFO", "Raid size changed from %d to %d. Creating new raid session.", current.size, desiredSize)
					addon:Print(L.StrNewRaidSessionChange)
					Raid:Create(instanceName, desiredSize)
				end
			end
		end
	end

	-- Checks the raid status upon player's login:
	function Raid:FirstCheck()
		Utils.unschedule(addon.Raid.FirstCheck)
		if GetNumRaidMembers() == 0 then return end

		-- We are in a raid? We update roster
		if KRT_CurrentRaid and Raid:CheckPlayer(unitName, KRT_CurrentRaid) then
			addon:Debug("DEBUG", "Player detected in active raid. Scheduling roster update.")
			Utils.schedule(2, addon.UpdateRaidRoster)
			return
		end

		local instanceName, instanceType, instanceDiff = GetInstanceInfo()
		if instanceType == "raid" then
			addon:Debug("DEBUG", "In raid instance on login. Checking raid state.")
			Raid:Check(instanceName, instanceDiff)
		end
	end

	-- Add a player to the raid:
	function Raid:AddPlayer(t, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		-- We must check if the players existed or not
		if not raidNum or not t or not t.name then
			addon:Debug("ERROR", "Raid:AddPlayer called with invalid parameters (raidNum=%s, player=%s)", tostring(raidNum), tostring(t and t.name))
			return
		end
		local players = Raid:GetPlayers(raidNum)
		local found = false
		for i, p in ipairs(players) do
			-- If found, we simply updated the table:
			if t.name == p.name then
				KRT_Raids[raidNum].players[i] = t
				found = true
				addon:Debug("DEBUG", "Updated existing player %s in raid %d", t.name, raidNum)
				break
			end
		end
		-- If the players wasn't in the raid, we add him/her:
		if not found then
		tinsert(KRT_Raids[raidNum].players, t)
			addon:Debug("INFO", "Added new player %s to raid %d", t.name, raidNum)
		end
	end

	-- Add a boss kill to the active raid:
	function Raid:AddBoss(bossName, manDiff, raidNum)
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not bossName then
			addon:Debug("ERROR", "Raid:AddBoss called with invalid parameters (raidNum=%s, bossName=%s)", tostring(raidNum), tostring(bossName))
			return
		end
		local _, _, instanceDiff, _, _, dynDiff, isDyn = GetInstanceInfo()
		if manDiff then
			instanceDiff = (KRT_Raids[raidNum].size == 10) and 1 or 2
			if lower(manDiff) == "h" then
				instanceDiff = instanceDiff + 2
			end
		elseif isDyn then
			instanceDiff = instanceDiff + (2 * dynDiff)
		end
		local players = {}
		for i = 1, GetNumRaidMembers() do
			local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
			if online == 1 then -- track only online players:
				tinsert(players, name)
			end
		end
		local currentTime = Utils.GetCurrentTime()
		local killInfo = {
			name = bossName,
			difficulty = instanceDiff,
			players = players,
			date = currentTime,
			hash = Utils.encode(raidNum.."|"..bossName.."|"..(KRT_LastBoss or "0"))
		}
		tinsert(KRT_Raids[raidNum].bossKills, killInfo)
		KRT_LastBoss = #KRT_Raids[raidNum].bossKills
		addon:Debug("INFO", "Boss kill recorded: '%s' [Difficulty %d] in Raid #%d with %d players. Time: %s", bossName, instanceDiff, raidNum, #players, currentTime)
	end

	-- Adds a loot to the active raid:
	function Raid:AddLoot(msg, rollType, rollValue)
		if not KRT_CurrentRaid then
			addon:Debug("ERROR", "Raid:AddLoot called with no active raid.")
			return
		end
		-- Master Loot Part:
		local player, itemLink, itemCount = deformat(msg, LOOT_ITEM_MULTIPLE)
		if not player then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ITEM)
		end
		if not player then
			player = unitName
			itemLink, itemCount = deformat(msg, msg, LOOT_ITEM_SELF_MULTIPLE)
		end
		if not itemLink then
			itemCount = 1
			itemLink = deformat(msg, LOOT_ITEM_SELF)
		end
		-- Master Loot Part:
		if not player or not itemLink then
			itemCount = 1
			player, itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			if not itemLink then
				player = unitName
				itemLink = deformat(msg, LOOT_ROLL_YOU_WON)
			end
		end

		if not itemLink then
			addon:Debug("DEBUG", "Loot message could not be parsed: %s", tostring(msg))
			return
		end
		-- Extract item information
		local _, _, itemString = string.find(itemLink, "^|c%x+|H(.+)|h%[.*%]")
		local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
		local _, _, _, _, itemId = string.find(itemLink, "|?c?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		itemId = tonumber(itemId)
		-- We don't proceed if lower then threshold or ignored:
		local lootThreshold = GetLootThreshold()
		if itemRarity and itemRarity < lootThreshold then
			addon:Debug("DEBUG", "Ignored item %s [%d] due to rarity (%d < %d)", itemName or "unknown", itemId or 0, itemRarity or -1, lootThreshold)
			return
		end
		if itemId and addon.ignoredItems[itemId] then
			addon:Debug("DEBUG", "Ignored item %s [%d] because it's in ignored list", itemName or "unknown", itemId)
			return
		end
		if not KRT_LastBoss then
			self:AddBoss("_TrashMob_")
		end
		rollType = rollType or currentRollType
		rollValue = rollValue or addon:HighestRoll()

		local lootInfo = {
			itemId      = itemId,
			itemName    = itemName,
			itemString  = itemString,
			itemLink    = itemLink,
			itemRarity  = itemRarity,
			itemTexture = itemTexture,
			itemCount   = itemCount,
			looter      = player,
			rollType    = rollType,
			rollValue   = rollValue,
			bossNum     = KRT_LastBoss,
			time        = Utils.GetCurrentTime(),
		}
		tinsert(KRT_Raids[KRT_CurrentRaid].loot, lootInfo)
		addon:Debug("INFO", "Loot added: %s x%d to %s [Raid #%d, Boss #%d, Rarity: %d, Roll: %s %s]", itemName or "unknown", itemCount, player, KRT_CurrentRaid, KRT_LastBoss or 0, itemRarity or -1, tostring(rollType), tostring(rollValue))
	end

	--------------------
	-- Raid Functions --
	--------------------

	-- Returns members count:
	function addon:GetNumRaid()
		addon:Debug("DEBUG", "GetNumRaid called. Current count: %d", numRaid)
		return numRaid
	end

	-- Returns raid size: 10 or 25
	function addon:GetRaidSize()
		local size = 0
		if self:IsInRaid() then
			local diff = GetRaidDifficulty()
			size = (diff == 1 or diff == 3) and 10 or 25
			addon:Debug("DEBUG", "GetRaidSize: Difficulty=%d, Size=%d", diff, size)
		else
			addon:Debug("DEBUG", "GetRaidSize: Not in a raid.")
		end
		return size
	end

	-- Return class color by name:
	do
		local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
		function addon:GetClassColor(name)
			name = (name == "DEATH KNIGHT") and "DEATHKNIGHT" or name
			if not colors[name] then
				addon:Debug("DEBUG", "GetClassColor: Unknown class '%s'", tostring(name))
				return 1, 1, 1
			end
			local c = colors[name]
			addon:Debug("DEBUG", "GetClassColor: %s = RGB(%.2f, %.2f, %.2f)", name, c.r, c.g, c.b)
			return c.r, c.g, c.b
		end
	end

	-- Checks if a raid is expired
	function Raid:Expired(rID)
		rID = rID or KRT_CurrentRaid
		if not rID or not KRT_Raids[rID] then
			addon:Debug("DEBUG", "Expired: Invalid or missing raid ID (%s)", tostring(rID))
			return true
		end
		local currentTime = Utils.GetCurrentTime()
		local startTime = KRT_Raids[rID].startTime
		local validDuration = (currentTime + KRT_NextReset) - startTime

		local isExpired = validDuration >= 604800 -- 7 days in seconds
		addon:Debug("DEBUG", "Expired: Raid #%d started at %d, now %d, duration %d => %s", rID, startTime, currentTime, validDuration, isExpired and "EXPIRED" or "ACTIVE")
		return isExpired
	end

	-- Retrieves the raid loot:
	function Raid:GetLoot(raidNum, bossNum)
		local items = {}
		raidNum = raidNum or KRT_CurrentRaid
		bossNum = bossNum or 0
		if not raidNum or not KRT_Raids[raidNum] then
			addon:Debug("DEBUG", "GetLoot: Invalid or missing raid ID (%s)", tostring(raidNum))
			return items
		end
		local loot = KRT_Raids[raidNum].loot
		local total = 0
		if tonumber(bossNum) <= 0 then
			for k, v in ipairs(loot) do
				local info = v
				info.id = k
				tinsert(items, info)
				total = total + 1
			end
			addon:Debug("DEBUG", "GetLoot: Retrieved all (%d) items for Raid #%d", total, raidNum)
		elseif KRT_Raids[raidNum].bossKills[bossNum] then
			for k, v in ipairs(loot) do
				if v.bossNum == bossNum then
					local info = v
					info.id = k
					tinsert(items, info)
					total = total + 1
				end
			end
			addon:Debug("DEBUG", "GetLoot: Retrieved %d items for Raid #%d, Boss #%d", total, raidNum, bossNum)
		else
			addon:Debug("DEBUG", "GetLoot: No loot found for Boss #%d in Raid #%d", bossNum, raidNum)
		end
		return items
	end

	-- Retrieves a loot item position within the raid loot:
	function Raid:GetLootID(itemID, raidNum, holderName)
		local pos = 0
		local loot = self:GetLoot(raidNum)
		holderName = holderName or unitName
		itemID = tonumber(itemID)
		for k, v in ipairs(loot) do
			if v.itemId == itemID and v.looter == holderName then
				pos = k
				addon:Debug("DEBUG", "GetLootID: Found item %d looted by '%s' at position %d (Raid #%s)", itemID, holderName, pos, tostring(raidNum or KRT_CurrentRaid))
				break
			end
		end
		if pos == 0 then
			addon:Debug("DEBUG", "GetLootID: Item %d looted by '%s' not found in Raid #%s", itemID, holderName, tostring(raidNum or KRT_CurrentRaid))
		end
		return pos
	end

	-- Retrieves raid bosses:
	function Raid:GetBosses(raidNum)
		local bosses = {}
		raidNum = raidNum or KRT_CurrentRaid
		if not raidNum or not KRT_Raids[raidNum] then
			addon:Debug("DEBUG", "GetBosses: Invalid or missing raid ID (%s)", tostring(raidNum))
			return bosses
		end
		local kills = KRT_Raids[raidNum].bossKills
		for i, b in ipairs(kills) do
			local info = {
				id = i,
				difficulty = b.difficulty,
				time = b.date,
				hash = b.hash or "0",
			}
			if b.name == "_TrashMob_" then
				info.name = L.StrTrashMob
				info.mode = ""
			else
				info.name = b.name
				info.mode = (b.difficulty == 3 or b.difficulty == 4) and PLAYER_DIFFICULTY2 or PLAYER_DIFFICULTY1
			end
			tinsert(bosses, info)
		end
		addon:Debug("DEBUG", "GetBosses: Retrieved %d boss kills for Raid #%d", #bosses, raidNum)
		return bosses
	end

	----------------------
	-- Player Functions --
	----------------------

	-- Returns current raid players:
	function Raid:GetPlayers(raidNum, bossNum)
		raidNum = raidNum or KRT_CurrentRaid
		local players = {}
		if not raidNum or not KRT_Raids[raidNum] then
			addon:Debug("DEBUG", "GetPlayers: Invalid or missing raid ID (%s)", tostring(raidNum))
			return players
		end
		for k, v in ipairs(KRT_Raids[raidNum].players) do
			local info = v
			v.id = k
			tinsert(players, info)
		end
			-- players = KRT_Raids[raidNum].players
		if bossNum and KRT_Raids[raidNum].bossKills[bossNum] then
			local _players = {}
			for i, p in ipairs(players) do
				if Utils.checkEntry(KRT_Raids[raidNum]["bossKills"][bossNum]["players"], p.name) then
					tinsert(_players, p)
				end
			end
			addon:Debug("DEBUG", "GetPlayers: Found %d players for Raid #%d, Boss #%d", #_players, raidNum, bossNum)
			return _players
		end
		addon:Debug("DEBUG", "GetPlayers: Found %d players for Raid #%d", #players, raidNum)
		return players
	end

	-- Checks if the given players in the raid:
	function Raid:CheckPlayer(name, raidNum)
		local found = false
		local players = Raid:GetPlayers(raidNum)
		local originalName = name
		if players ~= nil then
			name = ucfirst(name:trim())
			for i, p in ipairs(players) do
				if name == p.name then
					found = true
					break
				elseif strlen(name) >= 5 and p.name:startsWith(name) then
					name = p.name
					found = true
					break
				end
			end
		end
		addon:Debug("DEBUG", "CheckPlayer: %s (normalized to %s) found in raid %s: %s", originalName, name, tostring(raidNum or KRT_CurrentRaid), tostring(found))
		return found, name
	end

	-- Returns the players ID:
	function Raid:GetPlayerID(name, raidNum)
		local id = 0
		raidNum = raidNum or KRT_CurrentRaid
		name = name or unitName
		if raidNum and KRT_Raids[raidNum] then
			local players = KRT_Raids[raidNum].players
			for i, p in ipairs(players) do
				if p.name == name then
					id = i
					break
				end
			end
		end
		addon:Debug("DEBUG", "GetPlayerID: name=%s, raid=%s, resultID=%d", tostring(name), tostring(raidNum), id)
		return id
	end

	-- Get Player name:
	function Raid:GetPlayerName(id, raidNum)
		local name
		raidNum = raidNum or addon.Logger.selectedRaid or KRT_CurrentRaid
		if raidNum and KRT_Raids[raidNum] then
			for k, p in ipairs(KRT_Raids[raidNum].players) do
				if k == id then
					name = p.name
					break
				end
			end
		end
		addon:Debug("DEBUG", "GetPlayerName: id=%s, raid=%s, resultName=%s", tostring(id), tostring(raidNum), tostring(name))
		return name
	end

	-- Returns a table of items looted by the selected player:
	function Raid:GetPlayerLoot(name, raidNum, bossNum)
		local items = {}
		local loot = Raid:GetLoot(raidNum, bossNum)
		local originalName = name
		name = (type(name) == "number") and Raid:GetPlayerName(name) or name
		for k, v in ipairs(loot) do
			if v.looter == name then
				local info = v
				info.id = k
				tinsert(items, info)
			end
		end
		addon:Debug("DEBUG", "GetPlayerLoot: original=%s, resolvedName=%s, raid=%s, boss=%s, itemsFound=%d", tostring(originalName), tostring(name), tostring(raidNum or KRT_CurrentRaid), tostring(bossNum or "all"), #items)
		return items
	end

	-- Get player rank:
	function addon:GetPlayerRank(name, raidNum)
		local players = Raid:GetPlayers(raidNum)
		local rank = 0
		local originalName = name
		name = name or unitName or UnitName("player")
		if next(players) == nil then
			if GetNumRaidMembers() > 0 then
				numRaid = GetNumRaidMembers()
				for i = 1, numRaid do
					local pname, prank = GetRaidRosterInfo(i)
					if pname == name then
						rank = prank
						break
					end
				end
			end
		else
			for i, p in ipairs(players) do
				if p.name == name then
					rank = p.rank or 0
					break
				end
			end
		end
		addon:Debug("DEBUG", "GetPlayerRank: original=%s, resolvedName=%s, raid=%s, rank=%d", tostring(originalName), tostring(name), tostring(raidNum or KRT_CurrentRaid), rank)
		return rank
	end

	-- Get player class:
	function addon:GetPlayerClass(name)
		local class = "UNKNOWN"
		local realm = GetRealmName() or UNKNOWN
		local resolvedName = name or unitName
		if KRT_Players[realm] and KRT_Players[realm][resolvedName] then
			class = KRT_Players[realm][resolvedName].class or "UNKNOWN"
		end

		addon:Debug("DEBUG", "GetPlayerClass: name=%s, realm=%s, class=%s", tostring(resolvedName), tostring(realm), tostring(class))
		return class
	end

	-- Get player UnitID
	function addon:GetUnitID(name)
		local players = Raid:GetPlayers()
		local id = "none"
		local resolvedName = name
		if players then
			for i, p in ipairs(players) do
				if p.name == name then
					id = "raid"..tostring(i)
					break
				end
			end
		end
		addon:Debug("DEBUG", "GetUnitID: name=%s, unitID=%s", tostring(resolvedName), tostring(id))
		return id
	end

	-----------------------
	-- Raid & Loot Check --
	-----------------------

	-- Whether the player is a party group:
	function addon:IsInParty()
		local inParty = (GetNumPartyMembers() > 0) and (GetNumRaidMembers() == 0)
		addon:Debug("DEBUG", "IsInParty: %s", tostring(inParty))
		return inParty
	end

	-- Whether the player is a raid group:
	function addon:IsInRaid()
		local raidStatus = (inRaid == true or GetNumRaidMembers() > 0)
		addon:Debug("DEBUG", "IsInRaid: %s", tostring(raidStatus))
		return raidStatus
	end

	-- Check if the raid is using mater loot system:
	function addon:IsMasterLoot()
		local method = select(1, GetLootMethod())
		addon:Debug("DEBUG", "IsMasterLoot: method=%s", tostring(method))
		return (method == "master")
	end

	-- Check if the player is the master looter:
	function addon:IsMasterLooter()
		local method, partyID = GetLootMethod()
		local isML = (partyID and partyID == 0)
		addon:Debug("DEBUG", "IsMasterLooter: method=%s, partyID=%s => %s", tostring(method), tostring(partyID), tostring(isML))
		return isML
	end

	-- Utility : Clear all raid icons:
	function addon:ClearRaidIcons()
		local players = Raid:GetPlayers()
		for i, p in ipairs(players) do
			SetRaidTarget("raid"..tostring(i), 0)
		end
		addon:Debug("DEBUG", "ClearRaidIcons: Cleared icons for %d players", #players)
	end

