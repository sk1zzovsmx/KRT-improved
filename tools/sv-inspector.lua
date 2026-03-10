-- Offline SavedVariables inspector for KRT.
-- Usage:
--   lua tools/sv-inspector.lua <path-to-!KRT.lua>
--   lua tools/sv-inspector.lua <path-to-!KRT.lua> --format csv --section raids
--   lua tools/sv-inspector.lua <path-to-!KRT.lua> --format csv --section baseline --out baseline.csv

local tonumber, tostring, type = tonumber, tostring, type
local pairs = pairs
local concat = table.concat

local CURRENT_SCHEMA_VERSION = 3

local REQUIRED_SV_KEYS = {
    "KRT_Raids",
    "KRT_Players",
    "KRT_Reserves",
    "KRT_Warnings",
    "KRT_Spammer",
    "KRT_Options",
}

local CANONICAL_RAID_KEYS = {
    "raidNid",
    "schemaVersion",
    "players",
    "bossKills",
    "loot",
    "changes",
    "nextPlayerNid",
    "nextBossNid",
    "nextLootNid",
    "startTime",
}

local LEGACY_RAID_KEYS = {
    "_playersByName",
    "_playerIdxByNid",
    "_bossIdxByNid",
    "_lootIdxByNid",
}

local function countMapEntries(map)
    if type(map) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

local function toText(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function parseArgs(argv)
    local opts = {
        path = nil,
        format = "table",
        section = nil,
        outPath = nil,
        help = false,
    }

    local i = 1
    while i <= #argv do
        local token = argv[i]
        if token == "--help" or token == "-h" then
            opts.help = true
        elseif token == "--format" then
            i = i + 1
            opts.format = argv[i]
        elseif token:match("^%-%-format=") then
            opts.format = token:match("^%-%-format=(.+)$")
        elseif token == "--section" then
            i = i + 1
            opts.section = argv[i]
        elseif token:match("^%-%-section=") then
            opts.section = token:match("^%-%-section=(.+)$")
        elseif token == "--out" then
            i = i + 1
            opts.outPath = argv[i]
        elseif token:match("^%-%-out=") then
            opts.outPath = token:match("^%-%-out=(.+)$")
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

    if opts.format ~= "table" and opts.format ~= "csv" then
        return nil, "invalid --format (allowed: table, csv)"
    end

    if opts.format == "table" and not opts.section then
        opts.section = "all"
    end
    if opts.format == "csv" and not opts.section then
        opts.section = "raids"
    end

    local validSections = {
        all = true,
        baseline = true,
        raids = true,
        sanity = true,
    }
    if not validSections[opts.section] then
        return nil, "invalid --section (allowed: all, baseline, raids, sanity)"
    end

    return opts
end

local function printUsage()
    print("Usage:")
    print("  lua tools/sv-inspector.lua <path-to-!KRT.lua>")
    print("  lua tools/sv-inspector.lua <path> --format csv --section raids")
    print("  lua tools/sv-inspector.lua <path> --format csv --section baseline --out baseline.csv")
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

local function getFileSize(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local size = file:seek("end")
    file:close()
    return tonumber(size) or nil
end

local function countRealmPlayers(playersDb)
    local realmCount = 0
    local playerCount = 0
    if type(playersDb) ~= "table" then
        return realmCount, playerCount
    end

    for _, realmPlayers in pairs(playersDb) do
        if type(realmPlayers) == "table" then
            realmCount = realmCount + 1
            playerCount = playerCount + countMapEntries(realmPlayers)
        end
    end
    return realmCount, playerCount
end

local function countReserves(reservesDb)
    local playerCount = 0
    local reserveEntries = 0
    if type(reservesDb) ~= "table" then
        return playerCount, reserveEntries
    end

    for _, container in pairs(reservesDb) do
        if type(container) == "table" then
            playerCount = playerCount + 1
            local rows = container.reserves
            if type(rows) == "table" then
                reserveEntries = reserveEntries + #rows
            end
        end
    end
    return playerCount, reserveEntries
end

local function inspectRaid(raid, raidIndex)
    if type(raid) ~= "table" then
        return {
            raidIndex = raidIndex,
            raidNid = "",
            schemaVersion = "",
            playersCount = 0,
            bossKillsCount = 0,
            lootCount = 0,
            holder = "",
            banker = "",
            disenchanter = "",
            missingCanonicalCount = #CANONICAL_RAID_KEYS,
            missingCanonicalKeys = concat(CANONICAL_RAID_KEYS, ";"),
            legacyRuntimeCount = 0,
            legacyRuntimeKeys = "",
            legacyLootLooterCount = 0,
            legacyAttendanceMaskCount = 0,
            schemaOk = false,
            countersOk = false,
            referencesOk = false,
            missingLootBossRefs = 0,
            missingLootLooterRefs = 0,
            missingBossAttendeeRefs = 0,
        }
    end

    local players = (type(raid.players) == "table") and raid.players or {}
    local bosses = (type(raid.bossKills) == "table") and raid.bossKills or {}
    local lootRows = (type(raid.loot) == "table") and raid.loot or {}

    local missingCanonicalKeys = {}
    for i = 1, #CANONICAL_RAID_KEYS do
        local key = CANONICAL_RAID_KEYS[i]
        if raid[key] == nil then
            missingCanonicalKeys[#missingCanonicalKeys + 1] = key
        end
    end

    local legacyRuntimeKeys = {}
    for i = 1, #LEGACY_RAID_KEYS do
        local key = LEGACY_RAID_KEYS[i]
        if raid[key] ~= nil then
            legacyRuntimeKeys[#legacyRuntimeKeys + 1] = key
        end
    end

    local validPlayerNids = {}
    local bossByNid = {}
    local maxPlayerNid = 0
    local maxBossNid = 0
    local maxLootNid = 0

    for i = 1, #players do
        local player = players[i]
        if type(player) == "table" then
            local playerNid = tonumber(player.playerNid)
            if playerNid and playerNid > 0 then
                validPlayerNids[playerNid] = true
                if playerNid > maxPlayerNid then
                    maxPlayerNid = playerNid
                end
            end
        end
    end

    local missingBossAttendeeRefs = 0
    local legacyAttendanceMaskCount = 0
    for i = 1, #bosses do
        local boss = bosses[i]
        if type(boss) == "table" then
            local bossNid = tonumber(boss.bossNid)
            if bossNid and bossNid > 0 then
                bossByNid[bossNid] = true
                if bossNid > maxBossNid then
                    maxBossNid = bossNid
                end
            end

            if boss.attendanceMask ~= nil then
                legacyAttendanceMaskCount = legacyAttendanceMaskCount + 1
            end

            local attendees = boss.players
            if type(attendees) == "table" then
                for j = 1, #attendees do
                    local attendeeNid = tonumber(attendees[j]) or 0
                    if attendeeNid > 0 and not validPlayerNids[attendeeNid] then
                        missingBossAttendeeRefs = missingBossAttendeeRefs + 1
                    end
                end
            end
        end
    end

    local missingLootBossRefs = 0
    local missingLootLooterRefs = 0
    local legacyLootLooterCount = 0
    for i = 1, #lootRows do
        local loot = lootRows[i]
        if type(loot) == "table" then
            local lootNid = tonumber(loot.lootNid)
            if lootNid and lootNid > maxLootNid then
                maxLootNid = lootNid
            end

            if loot.looter ~= nil then
                legacyLootLooterCount = legacyLootLooterCount + 1
            end

            local bossNid = tonumber(loot.bossNid) or 0
            if bossNid > 0 and not bossByNid[bossNid] then
                missingLootBossRefs = missingLootBossRefs + 1
            end

            local looterNid = tonumber(loot.looterNid) or 0
            if looterNid > 0 and not validPlayerNids[looterNid] then
                missingLootLooterRefs = missingLootLooterRefs + 1
            end
        end
    end

    local nextPlayerNid = tonumber(raid.nextPlayerNid) or 0
    local nextBossNid = tonumber(raid.nextBossNid) or 0
    local nextLootNid = tonumber(raid.nextLootNid) or 0

    local countersOk = true
    if nextPlayerNid < (maxPlayerNid + 1) then
        countersOk = false
    end
    if nextBossNid < (maxBossNid + 1) then
        countersOk = false
    end
    if nextLootNid < (maxLootNid + 1) then
        countersOk = false
    end

    local schemaVersion = tonumber(raid.schemaVersion)
    local schemaOk = false
    if schemaVersion and schemaVersion >= 1 and schemaVersion <= CURRENT_SCHEMA_VERSION then
        schemaOk = true
    end

    local referencesOk = (missingBossAttendeeRefs == 0)
        and (missingLootBossRefs == 0)
        and (missingLootLooterRefs == 0)

    local holder = (type(raid.holder) == "string") and raid.holder or ""
    local banker = (type(raid.banker) == "string") and raid.banker or ""
    local disenchanter = (type(raid.disenchanter) == "string") and raid.disenchanter or ""

    return {
        raidIndex = raidIndex,
        raidNid = tonumber(raid.raidNid) or "",
        schemaVersion = schemaVersion or "",
        playersCount = #players,
        bossKillsCount = #bosses,
        lootCount = #lootRows,
        holder = holder,
        banker = banker,
        disenchanter = disenchanter,
        missingCanonicalCount = #missingCanonicalKeys,
        missingCanonicalKeys = concat(missingCanonicalKeys, ";"),
        legacyRuntimeCount = #legacyRuntimeKeys,
        legacyRuntimeKeys = concat(legacyRuntimeKeys, ";"),
        legacyLootLooterCount = legacyLootLooterCount,
        legacyAttendanceMaskCount = legacyAttendanceMaskCount,
        schemaOk = schemaOk,
        countersOk = countersOk,
        referencesOk = referencesOk,
        missingLootBossRefs = missingLootBossRefs,
        missingLootLooterRefs = missingLootLooterRefs,
        missingBossAttendeeRefs = missingBossAttendeeRefs,
    }
end

local function buildReport(env, sourcePath)
    local report = {
        baseline = {},
        raids = {},
        sanity = {},
    }

    local raids = (type(env.KRT_Raids) == "table") and env.KRT_Raids or {}
    local playersDb = (type(env.KRT_Players) == "table") and env.KRT_Players or {}
    local reservesDb = (type(env.KRT_Reserves) == "table") and env.KRT_Reserves or {}
    local warningsDb = (type(env.KRT_Warnings) == "table") and env.KRT_Warnings or {}
    local spammerDb = (type(env.KRT_Spammer) == "table") and env.KRT_Spammer or {}
    local optionsDb = (type(env.KRT_Options) == "table") and env.KRT_Options or {}

    local playerRealms, playersCount = countRealmPlayers(playersDb)
    local reservePlayers, reserveEntries = countReserves(reservesDb)

    local baseline = report.baseline
    baseline.filePath = sourcePath
    baseline.fileSizeBytes = getFileSize(sourcePath) or 0
    baseline.raids = #raids
    baseline.raidPlayers = 0
    baseline.raidBossKills = 0
    baseline.raidLoot = 0
    baseline.playerRealms = playerRealms
    baseline.playerEntries = playersCount
    baseline.reservePlayers = reservePlayers
    baseline.reserveEntries = reserveEntries
    baseline.warningEntries = countMapEntries(warningsDb)
    baseline.spammerKeys = countMapEntries(spammerDb)
    baseline.optionsKeys = countMapEntries(optionsDb)

    local sanity = report.sanity
    sanity.missingTopLevelKeys = {}
    for i = 1, #REQUIRED_SV_KEYS do
        local key = REQUIRED_SV_KEYS[i]
        if type(env[key]) ~= "table" then
            sanity.missingTopLevelKeys[#sanity.missingTopLevelKeys + 1] = key
        end
    end

    sanity.raidsWithSchemaIssue = 0
    sanity.raidsWithMissingCanonical = 0
    sanity.raidsWithLegacyRuntime = 0
    sanity.raidsWithLegacyLootLooter = 0
    sanity.raidsWithLegacyAttendanceMask = 0
    sanity.raidsWithCounterIssue = 0
    sanity.raidsWithReferenceIssue = 0

    for i = 1, #raids do
        local row = inspectRaid(raids[i], i)
        report.raids[#report.raids + 1] = row

        baseline.raidPlayers = baseline.raidPlayers + row.playersCount
        baseline.raidBossKills = baseline.raidBossKills + row.bossKillsCount
        baseline.raidLoot = baseline.raidLoot + row.lootCount

        if not row.schemaOk then
            sanity.raidsWithSchemaIssue = sanity.raidsWithSchemaIssue + 1
        end
        if row.missingCanonicalCount > 0 then
            sanity.raidsWithMissingCanonical = sanity.raidsWithMissingCanonical + 1
        end
        if row.legacyRuntimeCount > 0 then
            sanity.raidsWithLegacyRuntime = sanity.raidsWithLegacyRuntime + 1
        end
        if row.legacyLootLooterCount > 0 then
            sanity.raidsWithLegacyLootLooter = sanity.raidsWithLegacyLootLooter + 1
        end
        if row.legacyAttendanceMaskCount > 0 then
            sanity.raidsWithLegacyAttendanceMask = sanity.raidsWithLegacyAttendanceMask + 1
        end
        if not row.countersOk then
            sanity.raidsWithCounterIssue = sanity.raidsWithCounterIssue + 1
        end
        if not row.referencesOk then
            sanity.raidsWithReferenceIssue = sanity.raidsWithReferenceIssue + 1
        end
    end

    return report
end

local function createWriter(outPath)
    if not outPath or outPath == "" then
        return function(line)
            print(line)
        end, function()
        end
    end

    local file, err = io.open(outPath, "wb")
    if not file then
        return nil, nil, "cannot open output file: " .. tostring(err)
    end

    local function writeLine(line)
        file:write(line or "")
        file:write("\n")
    end

    local function closeWriter()
        file:close()
    end

    return writeLine, closeWriter
end

local function padRight(text, width)
    text = toText(text)
    local padding = width - #text
    if padding <= 0 then
        return text
    end
    return text .. string.rep(" ", padding)
end

local function renderAsciiTable(writeLine, headers, rows)
    local widths = {}
    for i = 1, #headers do
        widths[i] = #headers[i]
    end

    for r = 1, #rows do
        local row = rows[r]
        for c = 1, #headers do
            local cell = toText(row[c])
            if #cell > widths[c] then
                widths[c] = #cell
            end
        end
    end

    local ruleParts = {}
    for i = 1, #headers do
        ruleParts[i] = string.rep("-", widths[i])
    end
    local rule = "+-" .. concat(ruleParts, "-+-") .. "-+"

    writeLine(rule)
    local headerCells = {}
    for i = 1, #headers do
        headerCells[i] = padRight(headers[i], widths[i])
    end
    writeLine("| " .. concat(headerCells, " | ") .. " |")
    writeLine(rule)

    for r = 1, #rows do
        local row = rows[r]
        local out = {}
        for c = 1, #headers do
            out[c] = padRight(row[c], widths[c])
        end
        writeLine("| " .. concat(out, " | ") .. " |")
    end
    writeLine(rule)
end

local function csvEscape(value)
    local text = toText(value)
    if text:find("[,\r\n\"]") then
        text = "\"" .. text:gsub("\"", "\"\"") .. "\""
    end
    return text
end

local function writeCsvRow(writeLine, columns)
    local out = {}
    for i = 1, #columns do
        out[i] = csvEscape(columns[i])
    end
    writeLine(concat(out, ","))
end

local function boolText(value)
    if value then
        return "yes"
    end
    return "no"
end

local function emitBaselineTable(writeLine, report)
    local baseline = report.baseline
    local rows = {
        { "filePath", baseline.filePath },
        { "fileSizeBytes", baseline.fileSizeBytes },
        { "raids", baseline.raids },
        { "raid.players.total", baseline.raidPlayers },
        { "raid.bossKills.total", baseline.raidBossKills },
        { "raid.loot.total", baseline.raidLoot },
        { "KRT_Players.realms", baseline.playerRealms },
        { "KRT_Players.entries", baseline.playerEntries },
        { "KRT_Reserves.players", baseline.reservePlayers },
        { "KRT_Reserves.entries", baseline.reserveEntries },
        { "KRT_Warnings.entries", baseline.warningEntries },
        { "KRT_Spammer.keys", baseline.spammerKeys },
        { "KRT_Options.keys", baseline.optionsKeys },
    }

    writeLine("SV Baseline")
    renderAsciiTable(writeLine, { "metric", "value" }, rows)
end

local function emitRaidsTable(writeLine, report)
    local rows = {}
    for i = 1, #report.raids do
        local raid = report.raids[i]
        rows[#rows + 1] = {
            raid.raidIndex,
            raid.raidNid,
            raid.schemaVersion,
            raid.playersCount,
            raid.bossKillsCount,
            raid.lootCount,
            (raid.holder ~= "" and raid.holder or "-"),
            raid.missingCanonicalCount,
            raid.legacyRuntimeCount,
            raid.legacyLootLooterCount,
            raid.legacyAttendanceMaskCount,
            (raid.countersOk and "ok" or "bad"),
            (raid.referencesOk and "ok" or "bad"),
        }
    end

    writeLine("Raid Snapshot")
    renderAsciiTable(writeLine,
        { "idx", "raidNid", "schema", "players", "bossKills", "loot", "holder", "miss", "legacy", "looter",
            "mask", "ctr", "refs" },
        rows)
end

local function emitSanityTable(writeLine, report)
    local sanity = report.sanity

    local missingTopLevel = "none"
    if #sanity.missingTopLevelKeys > 0 then
        missingTopLevel = concat(sanity.missingTopLevelKeys, ";")
    end

    local rows = {
        { "topLevelKeysPresent", boolText(#sanity.missingTopLevelKeys == 0), missingTopLevel },
        { "schemaVersion", boolText(sanity.raidsWithSchemaIssue == 0), sanity.raidsWithSchemaIssue },
        {
            "canonicalRaidKeys",
            boolText(sanity.raidsWithMissingCanonical == 0),
            sanity.raidsWithMissingCanonical,
        },
        { "legacyRuntimeKeys", boolText(sanity.raidsWithLegacyRuntime == 0), sanity.raidsWithLegacyRuntime },
        {
            "legacyLootLooter",
            boolText(sanity.raidsWithLegacyLootLooter == 0),
            sanity.raidsWithLegacyLootLooter,
        },
        {
            "legacyAttendanceMask",
            boolText(sanity.raidsWithLegacyAttendanceMask == 0),
            sanity.raidsWithLegacyAttendanceMask,
        },
        { "nidCounters", boolText(sanity.raidsWithCounterIssue == 0), sanity.raidsWithCounterIssue },
        { "nidReferences", boolText(sanity.raidsWithReferenceIssue == 0), sanity.raidsWithReferenceIssue },
    }

    writeLine("SV Sanity")
    renderAsciiTable(writeLine, { "check", "pass", "details" }, rows)
end

local function emitBaselineCsv(writeLine, report)
    local baseline = report.baseline
    writeCsvRow(writeLine, { "metric", "value" })
    writeCsvRow(writeLine, { "filePath", baseline.filePath })
    writeCsvRow(writeLine, { "fileSizeBytes", baseline.fileSizeBytes })
    writeCsvRow(writeLine, { "raids", baseline.raids })
    writeCsvRow(writeLine, { "raid.players.total", baseline.raidPlayers })
    writeCsvRow(writeLine, { "raid.bossKills.total", baseline.raidBossKills })
    writeCsvRow(writeLine, { "raid.loot.total", baseline.raidLoot })
    writeCsvRow(writeLine, { "KRT_Players.realms", baseline.playerRealms })
    writeCsvRow(writeLine, { "KRT_Players.entries", baseline.playerEntries })
    writeCsvRow(writeLine, { "KRT_Reserves.players", baseline.reservePlayers })
    writeCsvRow(writeLine, { "KRT_Reserves.entries", baseline.reserveEntries })
    writeCsvRow(writeLine, { "KRT_Warnings.entries", baseline.warningEntries })
    writeCsvRow(writeLine, { "KRT_Spammer.keys", baseline.spammerKeys })
    writeCsvRow(writeLine, { "KRT_Options.keys", baseline.optionsKeys })
end

local function emitRaidsCsv(writeLine, report)
    writeCsvRow(writeLine, {
        "raidIndex",
        "raidNid",
        "schemaVersion",
        "players",
        "bossKills",
        "loot",
        "holder",
        "banker",
        "disenchanter",
        "missingCanonicalCount",
        "missingCanonicalKeys",
        "legacyRuntimeCount",
        "legacyRuntimeKeys",
        "legacyLootLooterCount",
        "legacyAttendanceMaskCount",
        "countersOk",
        "referencesOk",
        "missingLootBossRefs",
        "missingLootLooterRefs",
        "missingBossAttendeeRefs",
    })

    for i = 1, #report.raids do
        local raid = report.raids[i]
        writeCsvRow(writeLine, {
            raid.raidIndex,
            raid.raidNid,
            raid.schemaVersion,
            raid.playersCount,
            raid.bossKillsCount,
            raid.lootCount,
            raid.holder,
            raid.banker,
            raid.disenchanter,
            raid.missingCanonicalCount,
            raid.missingCanonicalKeys,
            raid.legacyRuntimeCount,
            raid.legacyRuntimeKeys,
            raid.legacyLootLooterCount,
            raid.legacyAttendanceMaskCount,
            boolText(raid.countersOk),
            boolText(raid.referencesOk),
            raid.missingLootBossRefs,
            raid.missingLootLooterRefs,
            raid.missingBossAttendeeRefs,
        })
    end
end

local function emitSanityCsv(writeLine, report)
    local sanity = report.sanity
    local missingTopLevel = "none"
    if #sanity.missingTopLevelKeys > 0 then
        missingTopLevel = concat(sanity.missingTopLevelKeys, ";")
    end

    writeCsvRow(writeLine, { "check", "pass", "details" })
    writeCsvRow(
        writeLine,
        { "topLevelKeysPresent", boolText(#sanity.missingTopLevelKeys == 0), missingTopLevel }
    )
    writeCsvRow(
        writeLine,
        { "schemaVersion", boolText(sanity.raidsWithSchemaIssue == 0), sanity.raidsWithSchemaIssue }
    )
    writeCsvRow(
        writeLine,
        {
            "canonicalRaidKeys",
            boolText(sanity.raidsWithMissingCanonical == 0),
            sanity.raidsWithMissingCanonical,
        }
    )
    writeCsvRow(
        writeLine,
        { "legacyRuntimeKeys", boolText(sanity.raidsWithLegacyRuntime == 0), sanity.raidsWithLegacyRuntime }
    )
    writeCsvRow(
        writeLine,
        {
            "legacyLootLooter",
            boolText(sanity.raidsWithLegacyLootLooter == 0),
            sanity.raidsWithLegacyLootLooter,
        }
    )
    writeCsvRow(
        writeLine,
        {
            "legacyAttendanceMask",
            boolText(sanity.raidsWithLegacyAttendanceMask == 0),
            sanity.raidsWithLegacyAttendanceMask,
        }
    )
    writeCsvRow(
        writeLine,
        { "nidCounters", boolText(sanity.raidsWithCounterIssue == 0), sanity.raidsWithCounterIssue }
    )
    writeCsvRow(
        writeLine,
        { "nidReferences", boolText(sanity.raidsWithReferenceIssue == 0), sanity.raidsWithReferenceIssue }
    )
end

local function emitTable(writeLine, report, section)
    if section == "baseline" then
        emitBaselineTable(writeLine, report)
        return
    end
    if section == "raids" then
        emitRaidsTable(writeLine, report)
        return
    end
    if section == "sanity" then
        emitSanityTable(writeLine, report)
        return
    end

    emitBaselineTable(writeLine, report)
    writeLine("")
    emitRaidsTable(writeLine, report)
    writeLine("")
    emitSanityTable(writeLine, report)
end

local function emitCsv(writeLine, report, section)
    if section == "baseline" then
        emitBaselineCsv(writeLine, report)
        return
    end
    if section == "raids" then
        emitRaidsCsv(writeLine, report)
        return
    end
    if section == "sanity" then
        emitSanityCsv(writeLine, report)
        return
    end

    emitBaselineCsv(writeLine, report)
    writeLine("")
    emitRaidsCsv(writeLine, report)
    writeLine("")
    emitSanityCsv(writeLine, report)
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

    local env, loadErr = loadSavedVariables(opts.path)
    if not env then
        print("[E] " .. tostring(loadErr))
        return 1
    end

    local report = buildReport(env, opts.path)

    local writeLine, closeWriter, outErr = createWriter(opts.outPath)
    if not writeLine then
        print("[E] " .. tostring(outErr))
        return 1
    end

    if opts.format == "csv" then
        emitCsv(writeLine, report, opts.section)
    else
        emitTable(writeLine, report, opts.section)
    end

    closeWriter()

    if opts.outPath and opts.outPath ~= "" then
        print("Wrote output to " .. opts.outPath)
    end
    return 0
end

local exitCode = run(arg or {})
if exitCode ~= 0 then
    os.exit(exitCode)
end
