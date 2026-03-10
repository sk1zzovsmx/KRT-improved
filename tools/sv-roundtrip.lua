-- Offline SavedVariables round-trip validator for KRT.
-- Usage:
--   lua tools/sv-roundtrip.lua <path-to-!KRT.lua>
--   lua tools/sv-roundtrip.lua <path-to-!KRT.lua> --verbose

local tonumber, tostring, type = tonumber, tostring, type
local pairs = pairs

local CURRENT_SCHEMA_VERSION = 3

local LEGACY_RUNTIME_KEYS = {
    "_playersByName",
    "_playerIdxByNid",
    "_bossIdxByNid",
    "_lootIdxByNid",
}

local RESERVE_ENTRY_PERSISTED_FIELDS = {
    "rawID",
    "itemLink",
    "itemName",
    "itemIcon",
    "quantity",
    "class",
    "spec",
    "note",
    "plus",
    "source",
}

local function parseArgs(argv)
    local opts = {
        path = nil,
        verbose = false,
        help = false,
    }

    local i = 1
    while i <= #argv do
        local token = argv[i]
        if token == "--help" or token == "-h" then
            opts.help = true
        elseif token == "--verbose" or token == "-v" then
            opts.verbose = true
        elseif token:sub(1, 2) == "--" then
            return nil, "unknown option: " .. token
        elseif not opts.path then
            opts.path = token
        else
            return nil, "unexpected argument: " .. token
        end
        i = i + 1
    end

    if opts.help then
        return opts
    end
    if not opts.path or opts.path == "" then
        return nil, "missing path to SavedVariables file"
    end
    return opts
end

local function printUsage()
    print("Usage:")
    print("  lua tools/sv-roundtrip.lua <path-to-!KRT.lua>")
    print("  lua tools/sv-roundtrip.lua <path-to-!KRT.lua> --verbose")
end

local function trimText(value)
    if value == nil then
        return nil
    end
    local text = tostring(value)
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function normalizeLower(value)
    local text = trimText(value)
    if not text then
        return nil
    end
    return string.lower(text)
end

local function normalizeName(value)
    return trimText(value)
end

local function normalizeReservePlayerDisplayName(value)
    local text = trimText(value)
    if not text then
        return nil
    end
    text = string.lower(text)
    return string.gsub(text, "%a", string.upper, 1)
end

local function normalizeTextOrNil(value)
    return trimText(value)
end

local function normalizePositiveNumberOrNil(value)
    local num = tonumber(value)
    if not num or num <= 0 then
        return nil
    end
    return num
end

local function normalizeNonNegativeNumber(value, fallback)
    local num = tonumber(value)
    if num == nil then
        num = fallback or 0
    end
    if num < 0 then
        num = fallback or 0
    end
    return num
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return out
end

local function formatPath(path, key)
    if type(key) == "number" then
        return path .. "[" .. tostring(key) .. "]"
    end
    return path .. "." .. tostring(key)
end

local function firstDiff(left, right, path, seenLeft, seenRight)
    local leftType = type(left)
    local rightType = type(right)
    if leftType ~= rightType then
        return path, left, right
    end

    if leftType ~= "table" then
        if left ~= right then
            return path, left, right
        end
        return nil
    end

    seenLeft = seenLeft or {}
    seenRight = seenRight or {}
    if seenLeft[left] and seenRight[right] then
        return nil
    end
    seenLeft[left] = true
    seenRight[right] = true

    for key, item in pairs(left) do
        if right[key] == nil then
            return formatPath(path, key), item, nil
        end
        local diffPath, diffLeft, diffRight = firstDiff(item, right[key], formatPath(path, key), seenLeft, seenRight)
        if diffPath then
            return diffPath, diffLeft, diffRight
        end
    end

    for key, item in pairs(right) do
        if left[key] == nil then
            return formatPath(path, key), nil, item
        end
    end

    return nil
end

local function allocateNid(preferred, used, nextNid)
    local candidate = tonumber(preferred)
    if candidate and candidate > 0 and not used[candidate] then
        used[candidate] = true
        if candidate >= nextNid then
            nextNid = candidate + 1
        end
        return candidate, nextNid
    end

    while used[nextNid] do
        nextNid = nextNid + 1
    end
    local out = nextNid
    used[out] = true
    return out, nextNid + 1
end

local function compactChangesMap(changes)
    local out = {}
    if type(changes) ~= "table" then
        return out
    end

    for rawName, rawSpec in pairs(changes) do
        local name = normalizeName(rawName)
        local spec = normalizeName(rawSpec)
        if name and spec then
            out[name] = spec
        end
    end
    return out
end

local function compactRaidForPersistence(raid)
    local players = (type(raid.players) == "table") and raid.players or {}
    for i = 1, #players do
        local player = players[i]
        if type(player) == "table" then
            local count = tonumber(player.count) or 0
            if count < 0 then
                count = 0
            end
            player.count = count

            local rank = tonumber(player.rank) or 0
            player.rank = (rank > 0) and rank or nil

            local subgroup = tonumber(player.subgroup) or 1
            player.subgroup = (subgroup > 1) and subgroup or nil

            player.join = normalizePositiveNumberOrNil(player.join)
            player.leave = normalizePositiveNumberOrNil(player.leave)

            local playerName = normalizeName(player.name)
            if playerName then
                player.name = playerName
            end

            local className = normalizeTextOrNil(player.class)
            player.class = className or "UNKNOWN"
        end
    end

    local bosses = (type(raid.bossKills) == "table") and raid.bossKills or {}
    for i = 1, #bosses do
        local boss = bosses[i]
        if type(boss) == "table" then
            local difficulty = tonumber(boss.difficulty) or 0
            boss.difficulty = (difficulty > 0) and difficulty or nil

            local mode = normalizeLower(boss.mode)
            local derived = nil
            if difficulty > 0 then
                derived = (difficulty == 3 or difficulty == 4) and "h" or "n"
            end
            if mode == "h" or mode == "n" then
                boss.mode = (mode ~= derived) and mode or nil
            else
                boss.mode = nil
            end

            boss.time = normalizePositiveNumberOrNil(boss.time)
            boss.hash = normalizeTextOrNil(boss.hash)
            boss.attendanceMask = nil

            local attendees = {}
            local seen = {}
            local rawPlayers = boss.players
            if type(rawPlayers) == "table" then
                for j = 1, #rawPlayers do
                    local playerNid = tonumber(rawPlayers[j])
                    if playerNid and playerNid > 0 and not seen[playerNid] then
                        seen[playerNid] = true
                        attendees[#attendees + 1] = playerNid
                    end
                end
            end
            boss.players = attendees
        end
    end

    local lootRows = (type(raid.loot) == "table") and raid.loot or {}
    for i = 1, #lootRows do
        local loot = lootRows[i]
        if type(loot) == "table" then
            loot.itemId = normalizePositiveNumberOrNil(loot.itemId)
            loot.itemName = normalizeTextOrNil(loot.itemName)
            loot.itemString = normalizeTextOrNil(loot.itemString)
            loot.itemLink = normalizeTextOrNil(loot.itemLink)
            loot.itemTexture = normalizeTextOrNil(loot.itemTexture)
            loot.rollSessionId = normalizeTextOrNil(loot.rollSessionId)
            loot.source = normalizeTextOrNil(loot.source)

            local itemRarity = tonumber(loot.itemRarity) or 0
            loot.itemRarity = (itemRarity > 0) and itemRarity or nil

            local itemCount = tonumber(loot.itemCount) or 1
            if itemCount < 1 then
                itemCount = 1
            end
            loot.itemCount = (itemCount > 1) and itemCount or nil

            local looterNid = tonumber(loot.looterNid)
            if looterNid and looterNid > 0 then
                loot.looterNid = looterNid
            else
                loot.looterNid = nil
            end
            loot.looter = nil

            local rollType = tonumber(loot.rollType) or 0
            loot.rollType = (rollType ~= 0) and rollType or nil

            local rollValue = tonumber(loot.rollValue) or 0
            loot.rollValue = (rollValue ~= 0) and rollValue or nil

            local bossNid = tonumber(loot.bossNid) or 0
            loot.bossNid = (bossNid > 0) and bossNid or nil

            loot.time = normalizePositiveNumberOrNil(loot.time)
        end
    end

    raid.changes = compactChangesMap(raid.changes)
    return raid
end

local function normalizeRaidRecord(rawRaid, currentSchemaVersion)
    if type(rawRaid) ~= "table" then
        return nil
    end

    local raid = deepCopy(rawRaid)
    local schemaVersion = tonumber(raid.schemaVersion) or currentSchemaVersion
    if schemaVersion < 1 then
        schemaVersion = currentSchemaVersion
    end
    if schemaVersion > currentSchemaVersion then
        schemaVersion = currentSchemaVersion
    end
    raid.schemaVersion = schemaVersion

    raid.players = (type(raid.players) == "table") and raid.players or {}
    raid.bossKills = (type(raid.bossKills) == "table") and raid.bossKills or {}
    raid.loot = (type(raid.loot) == "table") and raid.loot or {}
    raid.changes = (type(raid.changes) == "table") and raid.changes or {}

    local usedPlayerNids = {}
    local nextPlayerNid = normalizeNonNegativeNumber(raid.nextPlayerNid, 1)
    if nextPlayerNid < 1 then
        nextPlayerNid = 1
    end

    local playerNidByName = {}
    local validPlayerNids = {}
    for i = 1, #raid.players do
        local player = raid.players[i]
        if type(player) == "table" then
            local playerNid
            playerNid, nextPlayerNid = allocateNid(player.playerNid, usedPlayerNids, nextPlayerNid)
            player.playerNid = playerNid
            validPlayerNids[playerNid] = true

            local count = tonumber(player.count) or 0
            if count < 0 then
                count = 0
            end
            player.count = count

            local name = normalizeName(player.name)
            if name then
                player.name = name
                local lower = normalizeLower(name)
                if lower and playerNidByName[lower] == nil then
                    playerNidByName[lower] = playerNid
                end
            end
        end
    end

    local usedBossNids = {}
    local nextBossNid = normalizeNonNegativeNumber(raid.nextBossNid, 1)
    if nextBossNid < 1 then
        nextBossNid = 1
    end

    for i = 1, #raid.bossKills do
        local boss = raid.bossKills[i]
        if type(boss) == "table" then
            local bossNid
            bossNid, nextBossNid = allocateNid(boss.bossNid, usedBossNids, nextBossNid)
            boss.bossNid = bossNid

            local attendees = {}
            local seen = {}
            local rawPlayers = boss.players
            if type(rawPlayers) == "table" then
                for j = 1, #rawPlayers do
                    local rawPlayer = rawPlayers[j]
                    local playerNid = tonumber(rawPlayer)
                    if not playerNid and type(rawPlayer) == "string" then
                        playerNid = playerNidByName[normalizeLower(rawPlayer)]
                    end
                    if playerNid and playerNid > 0 and validPlayerNids[playerNid] and not seen[playerNid] then
                        seen[playerNid] = true
                        attendees[#attendees + 1] = playerNid
                    end
                end
            end
            boss.players = attendees
            boss.attendanceMask = nil
        end
    end

    local usedLootNids = {}
    local nextLootNid = normalizeNonNegativeNumber(raid.nextLootNid, 1)
    if nextLootNid < 1 then
        nextLootNid = 1
    end

    for i = 1, #raid.loot do
        local loot = raid.loot[i]
        if type(loot) == "table" then
            local lootNid
            lootNid, nextLootNid = allocateNid(loot.lootNid, usedLootNids, nextLootNid)
            loot.lootNid = lootNid

            local looterNid = tonumber(loot.looterNid)
            if looterNid and looterNid > 0 and validPlayerNids[looterNid] then
                loot.looterNid = looterNid
            else
                loot.looterNid = nil
            end
            loot.looter = nil
        end
    end

    raid.nextPlayerNid = nextPlayerNid
    raid.nextBossNid = nextBossNid
    raid.nextLootNid = nextLootNid
    raid.raidNid = tonumber(raid.raidNid)

    raid._runtime = nil
    for i = 1, #LEGACY_RUNTIME_KEYS do
        raid[LEGACY_RUNTIME_KEYS[i]] = nil
    end

    compactRaidForPersistence(raid)
    return raid
end

local function normalizeRaids(rawRaids, currentSchemaVersion)
    local raids = (type(rawRaids) == "table") and rawRaids or {}
    local out = {}

    local usedRaidNids = {}
    local nextRaidNid = 1
    for i = 1, #raids do
        local normalized = normalizeRaidRecord(raids[i], currentSchemaVersion)
        if normalized then
            local raidNid
            raidNid, nextRaidNid = allocateNid(normalized.raidNid, usedRaidNids, nextRaidNid)
            normalized.raidNid = raidNid
            out[#out + 1] = normalized
        end
    end

    return out
end

local function resolvePlayerNameDisplay(playerKey, player)
    local candidate = nil
    if type(player) == "table" then
        candidate = player.playerNameDisplay or player.original
    end
    candidate = normalizeReservePlayerDisplayName(candidate or playerKey)
    if not candidate or candidate == "" then
        return "?"
    end
    return candidate
end

local function copyReserveEntry(row)
    if type(row) ~= "table" or not row.rawID then
        return nil
    end

    local out = {}
    for i = 1, #RESERVE_ENTRY_PERSISTED_FIELDS do
        local key = RESERVE_ENTRY_PERSISTED_FIELDS[i]
        if row[key] ~= nil then
            out[key] = row[key]
        end
    end

    out.quantity = tonumber(out.quantity) or 1
    if out.quantity < 1 then
        out.quantity = 1
    end
    out.plus = tonumber(out.plus) or 0
    return out
end

local function normalizeReserves(rawReserves)
    local reserves = (type(rawReserves) == "table") and rawReserves or {}
    local runtime = {}

    for rawPlayerKey, player in pairs(reserves) do
        if type(player) == "table" then
            local displayName = resolvePlayerNameDisplay(rawPlayerKey, player)
            local playerKey = normalizeLower(displayName) or normalizeLower(rawPlayerKey) or tostring(rawPlayerKey or "")
            if playerKey == "" then
                playerKey = "?"
            end

            local container = runtime[playerKey]
            if not container then
                container = {
                    playerNameDisplay = displayName,
                    reserves = {},
                }
                runtime[playerKey] = container
            elseif not container.playerNameDisplay or container.playerNameDisplay == "?" then
                container.playerNameDisplay = displayName
            end

            local rows = player.reserves
            if type(rows) == "table" then
                for i = 1, #rows do
                    local copied = copyReserveEntry(rows[i])
                    if copied then
                        container.reserves[#container.reserves + 1] = copied
                    end
                end
            end
        end
    end

    local out = {}
    for playerKey, player in pairs(runtime) do
        if type(player) == "table" then
            local persistedKey = resolvePlayerNameDisplay(playerKey, player)
            local container = out[persistedKey]
            if not container then
                container = { reserves = {} }
                out[persistedKey] = container
            end

            local rows = player.reserves
            if type(rows) == "table" then
                for i = 1, #rows do
                    local copied = copyReserveEntry(rows[i])
                    if copied then
                        container.reserves[#container.reserves + 1] = copied
                    end
                end
            end
        end
    end

    return out
end

local function loadSavedVariables(path)
    local env = {}
    setmetatable(env, { __index = _G })

    local chunk, loadErr
    if _VERSION == "Lua 5.1" then
        chunk, loadErr = loadfile(path)
        if not chunk then
            return nil, "cannot load input file: " .. tostring(loadErr)
        end
        if setfenv then
            setfenv(chunk, env)
        end
    else
        chunk, loadErr = loadfile(path, "t", env)
        if not chunk then
            return nil, "cannot load input file: " .. tostring(loadErr)
        end
    end

    local ok, execErr = pcall(chunk)
    if not ok then
        return nil, "input execution failed: " .. tostring(execErr)
    end

    return env
end

local function normalizeSnapshot(sourceEnv)
    local normalized = {
        KRT_Raids = normalizeRaids(sourceEnv.KRT_Raids, CURRENT_SCHEMA_VERSION),
        KRT_Reserves = normalizeReserves(sourceEnv.KRT_Reserves),
    }
    return normalized
end

local function countReserveEntries(reservesDb)
    local players = 0
    local entries = 0
    if type(reservesDb) ~= "table" then
        return players, entries
    end

    for _, container in pairs(reservesDb) do
        if type(container) == "table" then
            players = players + 1
            local rows = container.reserves
            if type(rows) == "table" then
                entries = entries + #rows
            end
        end
    end
    return players, entries
end

local function runRoundTrip(path, verbose)
    local env, loadErr = loadSavedVariables(path)
    if not env then
        return false, loadErr
    end

    local pass1 = normalizeSnapshot(env)
    local pass2 = normalizeSnapshot(pass1)

    local raidDiffPath, raidLeft, raidRight = firstDiff(pass1.KRT_Raids, pass2.KRT_Raids, "KRT_Raids")
    local reservesDiffPath, reservesLeft, reservesRight = firstDiff(pass1.KRT_Reserves, pass2.KRT_Reserves, "KRT_Reserves")

    local reservePlayers, reserveEntries = countReserveEntries(pass1.KRT_Reserves)
    print(("[INFO] Input: %s"):format(path))
    print(("[INFO] Canonical snapshot: raids=%d reserves.players=%d reserves.entries=%d"):format(#pass1.KRT_Raids, reservePlayers, reserveEntries))

    local failed = false
    if raidDiffPath then
        failed = true
        print(("[E] Raid round-trip drift at %s"):format(raidDiffPath))
        if verbose then
            print(("    left=%s"):format(tostring(raidLeft)))
            print(("    right=%s"):format(tostring(raidRight)))
        end
    else
        print("[I] Raid round-trip stable")
    end

    if reservesDiffPath then
        failed = true
        print(("[E] Reserves round-trip drift at %s"):format(reservesDiffPath))
        if verbose then
            print(("    left=%s"):format(tostring(reservesLeft)))
            print(("    right=%s"):format(tostring(reservesRight)))
        end
    else
        print("[I] Reserves round-trip stable")
    end

    if failed then
        return false, "round-trip drift detected"
    end

    print("[PASS] Round-trip completed with no drift")
    return true
end

local function run(argv)
    local opts, parseErr = parseArgs(argv)
    if not opts then
        print("[E] " .. tostring(parseErr))
        printUsage()
        return 1
    end

    if opts.help then
        printUsage()
        return 0
    end

    local ok, err = runRoundTrip(opts.path, opts.verbose)
    if not ok then
        print("[E] " .. tostring(err))
        return 2
    end
    return 0
end

local exitCode = run(arg or {})
if exitCode ~= 0 then
    os.exit(exitCode)
end
