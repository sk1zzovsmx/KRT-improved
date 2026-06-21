local function read(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end

local function assertContains(text, needle, message)
    assert(text:find(needle, 1, true), message or ("missing: " .. needle))
end

local function assertNotContains(text, needle, message)
    assert(not text:find(needle, 1, true), message or ("unexpected: " .. needle))
end

local function countPlain(text, needle)
    local count = 0
    local startIndex = 1
    while true do
        local found = text:find(needle, startIndex, true)
        if not found then
            return count
        end
        count = count + 1
        startIndex = found + #needle
    end
end

local function assertNoLegacyOptionsProxy(path)
    assertNotContains(read(path), "addon.options", path .. " must use namespace cfg:Get instead of addon.options")
end

local function assertNoRootCurrentRaidLookup(path)
    assertNotContains(read(path), "addon.Database.GetCurrentRaid", path .. " must use local Database dependency for current raid lookup")
end

local function assertNoRootDependencyLookup(path, needle, dependencyName)
    assertNotContains(read(path), needle, path .. " must use local " .. dependencyName .. " dependency")
end

local function assertBefore(text, first, second, message)
    local firstIndex = text:find(first, 1, true)
    local secondIndex = text:find(second, 1, true)
    assert(firstIndex, "missing TOC entry: " .. first)
    assert(secondIndex, "missing TOC entry: " .. second)
    assert(firstIndex < secondIndex, message or (first .. " must load before " .. second))
end

local function collectQuotedValues(text)
    local values = {}
    for value in text:gmatch('"([^"]+)"') do
        values[#values + 1] = value
    end
    return values
end

local function assertDeps(actual, expected, context)
    assert(#actual == #expected, context .. " dependency count must match")
    for i = 1, #expected do
        assert(actual[i] == expected[i], context .. " dependency " .. i .. " must be " .. expected[i])
    end
end

local function findLastExportedFunction(source, owner, separator)
    local lastStart = nil
    local startIndex = 1
    local sepPattern = separator == "." and "%." or ":"
    local pattern = "function%s+" .. owner .. sepPattern .. "[%w_]+%s*%("

    while true do
        local found = source:find(pattern, startIndex)
        if not found then
            break
        end
        lastStart = found
        startIndex = found + 1
    end
    return lastStart
end

local function findLastExportedFunctionAny(source, owners)
    local lastStart = nil

    for i = 1, #owners do
        local spec = owners[i]
        local found = findLastExportedFunction(source, spec.owner, spec.separator)
        if found and (not lastStart or found > lastStart) then
            lastStart = found
        end
    end
    return lastStart
end

local function findExpectedPublicApi(source, expected)
    if expected.metadataAfterNeedle then
        return source:find(expected.metadataAfterNeedle, 1, true)
    end
    if expected.owners then
        return findLastExportedFunctionAny(source, expected.owners)
    end
    return findLastExportedFunction(source, expected.owner, expected.separator)
end

local function getPostRegistryDeps(source, moduleName)
    local registerStart = source:find('registry.AddModule("' .. moduleName .. '"', 1, true)
    assert(registerStart, moduleName .. " must direct-register dependency metadata")
    local depsStart = source:find("deps = {", registerStart, true)
    assert(depsStart, moduleName .. " must declare direct-register deps")
    local depsEnd = source:find("}", depsStart, true)
    assert(depsEnd, moduleName .. " must close direct-register deps")
    local depsText = source:sub(depsStart, depsEnd)
    return collectQuotedValues(depsText)
end

local preRegistryCoreModules = {
    { name = "Database/DB", deps = { "Init" } },
    { name = "Database/DBOptions", deps = { "Init" } },
    { name = "Database/DBSchema", deps = { "Init" } },
    { name = "Database/DBManager", deps = { "Init", "Database/DB" } },
}

local preRegistryUtilityModules = {
    { name = "Modules/C", deps = { "Init" } },
    { name = "Modules/Timer", deps = { "Init" } },
    { name = "Modules/Events", deps = { "Init" } },
    { name = "Modules/Colors", deps = { "Init" } },
    { name = "Modules/Strings", deps = { "Init", "Modules/Colors" } },
    { name = "Modules/Item", deps = { "Init", "Modules/Timer", "Modules/Strings" } },
    { name = "Modules/Dataset/LootSourcesData", deps = { "Init" } },
    { name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/Dataset/LootSourcesData" } },
    { name = "Modules/Dataset/IgnoredItems", deps = { "Init" } },
    { name = "Modules/Dataset/IgnoredMobs", deps = { "Init" } },
    { name = "Modules/Comms", deps = { "Init" } },
    { name = "Modules/Time", deps = { "Init" } },
    { name = "Modules/Base64", deps = { "Init" } },
    { name = "Modules/Json", deps = { "Init" } },
    { name = "Modules/Sort", deps = { "Init" } },
    { name = "Modules/Features", deps = { "Init" } },
}

local directRegistryModules = {
    { name = "Modules/UI/Facade", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Effects", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Effects" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames", "Modules/UI/Visuals" } },
    { name = "Modules/UI/MultiSelect", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/LootSourceCandidates", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" } },
    { name = "Modules/Bus", deps = { "Init", "Modules/ModuleRegistry" } },
}

local postRegistryCoreModules = {
    {
        name = "Database/DBRaidMigrations",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBSchema", "Modules/Strings" },
    },
    {
        name = "Database/DBRaidStore",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DB",
            "Database/DBSchema",
            "Database/DBRaidMigrations",
            "Modules/Time",
            "Modules/Strings",
        },
    },
    {
        name = "Database/DBRaidQueries",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DB", "Database/DBRaidStore", "Modules/Sort" },
    },
    {
        name = "Database/DBRaidValidator",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DB",
            "Database/DBSchema",
            "Database/DBRaidMigrations",
            "Database/DBRaidStore",
            "Modules/Dataset/IgnoredMobs",
        },
    },
    {
        name = "Database/DBSyncer",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DB",
            "Database/DBSchema",
            "Database/DBRaidStore",
            "Database/DBRaidQueries",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Time",
            "Modules/Comms",
        },
    },
}

local expectedService = {
    name = "Services/Chat",
    path = "!KRT/Services/Chat.lua",
    owner = "module",
    separator = ":",
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/C",
        "Modules/Timer",
        "Modules/Strings",
        "Modules/Comms",
    },
    events = "-- events: owns chat output helpers and LFM spam Timer ticker",
}

local expectedSpecInspectService = {
    name = "Services/SpecInspect",
    path = "!KRT/Services/SpecInspect.lua",
    owner = "module",
    separator = ":",
    registryFromFeature = true,
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/Events",
        "Modules/Bus",
        "Modules/Strings",
        "Services/Raid/Roster",
    },
    events = "-- events: listens wow.READY_CHECK and LibGroupTalents callbacks; emits SpecInspectUpdated",
}

local expectedSpammerServices = {
    {
        name = "Services/Spammer/Draft",
        path = "!KRT/Services/Spammer/Draft.lua",
        owner = "Draft",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure spammer draft/store/preview model helpers",
    },
    {
        name = "Services/Warnings/Store",
        path = "!KRT/Services/Warnings/Store.lua",
        owner = "Store",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure warnings saved-variable and template helpers",
    },
}

local expectedRollServices = {
    {
        name = "Services/Rolls/Countdown",
        path = "!KRT/Services/Rolls/Countdown.lua",
        owner = "Countdown",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Timer", "Services/Chat" },
        events = "-- events: announces countdown ticks through Services/Chat",
        note = "-- notes: countdown runtime helpers for rolls service",
    },
    {
        name = "Services/Rolls/Sessions",
        path = "!KRT/Services/Rolls/Sessions.lua",
        owner = "Sessions",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Modules/Strings" },
        events = "-- events: none",
        note = "-- notes: session and context helpers for rolls service",
    },
    {
        name = "Services/Rolls/History",
        path = "!KRT/Services/Rolls/History.lua",
        owner = "History",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus" },
        events = "-- events: emits AddRoll via addon.Bus",
        note = "-- notes: raw roll history and tracker helpers for rolls service",
    },
    {
        name = "Services/Rolls/Responses",
        path = "!KRT/Services/Rolls/Responses.lua",
        owner = "Responses",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Services/Chat" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves", "Services/Loot" },
        events = "-- events: announces countdown blocks and whispers denial reasons",
        note = "-- notes: response and eligibility helpers for rolls service",
    },
    {
        name = "Services/Rolls/Strategies",
        path = "!KRT/Services/Rolls/Strategies.lua",
        owner = "Strategies",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        events = "-- events: none",
        note = "-- notes: roll resolution strategy helpers",
    },
    {
        name = "Services/Rolls/Resolution",
        path = "!KRT/Services/Rolls/Resolution.lua",
        owner = "Resolution",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Strategies" },
        events = "-- events: none",
        note = "-- notes: resolution and display helpers for rolls service",
    },
    {
        name = "Services/Rolls/Display",
        path = "!KRT/Services/Rolls/Display.lua",
        owner = "Display",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Responses", "Services/Rolls/Resolution" },
        events = "-- events: none",
        note = "-- notes: display-model helpers for rolls service",
    },
    {
        name = "Services/Rolls/Service",
        path = "!KRT/Services/Rolls/Service.lua",
        owner = "module",
        separator = ":",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
            "Modules/Strings",
            "Services/Rolls/Countdown",
            "Services/Rolls/Sessions",
            "Services/Rolls/History",
            "Services/Rolls/Responses",
            "Services/Rolls/Strategies",
            "Services/Rolls/Resolution",
            "Services/Rolls/Display",
            "Services/Raid/State",
            "Services/Raid/LootRecords",
        },
        forbiddenDeps = { "Services/Raid", "Services/Reserves", "Services/Loot" },
        events = "-- events: emits AddRoll through History; owns countdown facade calls",
    },
}

local expectedLootServices = {
    {
        name = "Services/Loot/Context",
        path = "!KRT/Services/Loot/Context.lua",
        owners = { { owner = "LootContext", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/LootSourceCandidates" },
        events = "-- events: no bus events; context helpers only",
        note = "-- notes: bootstrap-sensitive internal loot helpers",
    },
    {
        name = "Services/Loot/State",
        path = "!KRT/Services/Loot/State.lua",
        owners = {
            { owner = "ContextState", separator = "." },
            { owner = "Sessions", separator = "." },
        },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Services/Loot/Context" },
        events = "-- events: no bus events; state helpers only",
        note = "-- notes: bootstrap-sensitive internal loot state helpers",
    },
    {
        name = "Services/Loot/Snapshots",
        path = "!KRT/Services/Loot/Snapshots.lua",
        owners = { { owner = "Snapshots", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Services/Loot/State", "Services/Loot/Context" },
        events = "-- events: no bus events; snapshot helpers only",
        note = "-- notes: internal loot-window snapshot helpers",
    },
    {
        name = "Services/Loot/PendingAwards",
        path = "!KRT/Services/Loot/PendingAwards.lua",
        owners = { { owner = "PendingAwards", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item" },
        events = "-- events: no bus events; pending-award helpers only",
        note = "-- notes: pending-award helpers for loot service",
    },
    {
        name = "Services/Loot/PassiveGroupLoot",
        path = "!KRT/Services/Loot/PassiveGroupLoot.lua",
        owners = { { owner = "PassiveGroupLoot", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Strings" },
        events = "-- events: no bus events; passive group-loot helpers only",
        note = "-- notes: passive group-loot parser/state helpers for loot service",
    },
    {
        name = "Services/Loot/Tracking",
        path = "!KRT/Services/Loot/Tracking.lua",
        owners = { { owner = "Tracking", separator = "." } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
            "Services/Loot/Context",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
        },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: no bus events; tracking helpers only",
        note = "-- notes: tracking/snapshot helpers for loot service",
    },
    {
        name = "Services/Loot/Workflow",
        path = "!KRT/Services/Loot/Workflow.lua",
        owners = { { owner = "Workflow", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry" },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: no bus events; shadow diagnostics only",
    },
    {
        name = "Services/Loot/Receipts",
        path = "!KRT/Services/Loot/Receipts.lua",
        owners = { { owner = "Receipts", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item" },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: no bus events; pure receipt classification helpers",
    },
    {
        name = "Services/Loot/Records",
        path = "!KRT/Services/Loot/Records.lua",
        owners = { { owner = "Records", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Time" },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: no bus events; append/build helpers only",
    },
    {
        name = "Services/Loot/Reconcile",
        path = "!KRT/Services/Loot/Reconcile.lua",
        owners = { { owner = "Reconcile", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: no bus events; reconciliation helpers only",
    },
    {
        name = "Services/Loot/Rules",
        path = "!KRT/Services/Loot/Rules.lua",
        owners = { { owner = "Rules", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Dataset/IgnoredItems" },
        events = "-- events: no bus events; suggestion-only classification",
    },
    {
        name = "Services/Loot/DistributionSession",
        path = "!KRT/Services/Loot/DistributionSession.lua",
        owners = { { owner = "DistributionSession", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Comms", "Modules/Item" },
        forbiddenDeps = { "Services/Raid" },
        events = "-- events: LootDistributionSessionChanged",
    },
    {
        name = "Services/Loot/Service",
        path = "!KRT/Services/Loot/Service.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Item",
            "Modules/Strings",
            "Modules/Time",
            "Database/DBRaidQueries",
            "Services/Loot/Context",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
            "Services/Loot/Tracking",
            "Services/Loot/Workflow",
            "Services/Loot/Receipts",
            "Services/Loot/Records",
            "Services/Loot/Reconcile",
            "Services/Loot/Rules",
        },
        forbiddenDeps = {
            "Services/Raid",
            "Services/Chat",
            "Services/Rolls/Service",
            "Services/Loot/DistributionSession",
        },
        events = "-- events: emits SetItem/RaidLootUpdate; delegates distribution messages",
    },
}

local expectedRaidServices = {
    {
        name = "Services/Raid/State",
        path = "!KRT/Services/Raid/State.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Time",
            "Modules/Base64",
            "Modules/Dataset/IgnoredMobs",
            "Modules/LootSources",
            "Database/DBRaidQueries",
            "Services/Loot/Context",
            "Services/Loot/State",
            "Services/Loot/Snapshots",
        },
        forbiddenDeps = {
            "Services/Loot/Service",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
            "Services/Loot/Tracking",
            "Services/Loot/Rules",
            "Services/Loot/DistributionSession",
            "Services/Chat",
            "Services/Rolls/Service",
        },
    },
    {
        name = "Services/Raid/Capabilities",
        path = "!KRT/Services/Raid/Capabilities.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry" },
        forbiddenDeps = { "Services/Chat" },
    },
    {
        name = "Services/Raid/Counts",
        path = "!KRT/Services/Raid/Counts.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Strings" },
    },
    {
        name = "Services/Raid/Roster",
        path = "!KRT/Services/Raid/Roster.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Time",
        },
    },
    {
        name = "Services/Raid/Attendance",
        path = "!KRT/Services/Raid/Attendance.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Time" },
    },
    {
        name = "Services/Raid/LootRecords",
        path = "!KRT/Services/Raid/LootRecords.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Item",
            "Modules/Strings",
            "Database/DBRaidQueries",
            "Services/Raid/Counts",
        },
    },
    {
        name = "Services/Raid/Session",
        path = "!KRT/Services/Raid/Session.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Services/Raid/LootMethod",
        path = "!KRT/Services/Raid/LootMethod.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Events",
            "Modules/Bus",
            "Database/DBOptions",
            "Services/Raid/Capabilities",
        },
        events = "-- events: listens forwarded PLAYER_TARGET_CHANGED through Master; emits RequestGroupLootRestorePrompt",
    },
}

local expectedLoggerServices = {
    {
        name = "Services/Logger/Store",
        path = "!KRT/Services/Logger/Store.lua",
        owner = "Store",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Database/DBRaidQueries", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Database/DBRaidStore" },
        registryFromFeature = true,
    },
    {
        name = "Services/Logger/View",
        path = "!KRT/Services/Logger/View.lua",
        owner = "View",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Sort", "Services/Logger/Store", "Modules/LootSourceCandidates" },
        forbiddenDeps = { "Services/Raid", "Database/DBRaidQueries", "Database/DBRaidStore" },
        registryFromFeature = true,
    },
    {
        name = "Services/Logger/Helpers",
        path = "!KRT/Services/Logger/Helpers.lua",
        owner = "Helpers",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Services/Logger/Store" },
        forbiddenDeps = { "Services/Raid", "Database/DBRaidQueries", "Database/DBRaidStore" },
        registryFromFeature = true,
    },
    {
        name = "Services/Logger/Export",
        path = "!KRT/Services/Logger/Export.lua",
        owner = "Export",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Logger/Store", "Services/Logger/Helpers" },
        forbiddenDeps = { "Services/Raid", "Database/DBRaidQueries", "Database/DBRaidStore" },
        registryFromFeature = true,
    },
    {
        name = "Services/Logger/Actions",
        path = "!KRT/Services/Logger/Actions.lua",
        owner = "Actions",
        separator = ":",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Timer",
            "Modules/Strings",
            "Modules/Base64",
            "Database/DBRaidQueries",
            "Services/Logger/Store",
            "Services/Logger/Helpers",
        },
        forbiddenDeps = { "Services/Raid", "Database/DBRaidStore" },
        registryFromFeature = true,
    },
}

local expectedReservesServices = {
    {
        name = "Services/Reserves/Import",
        path = "!KRT/Services/Reserves/Import.lua",
        metadataAfterNeedle = "ParseImport = parseImport,",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Base64", "Modules/Json" },
        forbiddenDeps = { "Services/Raid" },
        registryFromFeature = true,
        events = "-- events: no bus events; import parsing helpers only",
        note = "-- notes: reserves import parsing helpers",
    },
    {
        name = "Services/Reserves/Aliases",
        path = "!KRT/Services/Reserves/Aliases.lua",
        owner = "Aliases",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves" },
        registryFromFeature = true,
        events = "-- events: no bus events; alias helpers only",
        note = "-- notes: reserves name-alias helpers",
    },
    {
        name = "Services/Reserves/Display",
        path = "!KRT/Services/Reserves/Display.lua",
        owner = "Display",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings", "Services/Reserves/Aliases" },
        forbiddenDeps = { "Services/Raid" },
        registryFromFeature = true,
        events = "-- events: no bus events; display helpers only",
        note = "-- notes: reserves display/grouping helpers",
    },
    {
        name = "Services/Reserves/Sync",
        path = "!KRT/Services/Reserves/Sync.lua",
        owner = "Sync",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Comms", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves" },
        registryFromFeature = true,
        events = "-- events: handles KRTResSync addon-message traffic",
    },
    {
        name = "Services/Reserves",
        path = "!KRT/Services/Reserves.lua",
        owner = "Service",
        separator = ":",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Item",
            "Services/Reserves/Import",
            "Services/Reserves/Aliases",
            "Services/Reserves/Display",
        },
        forbiddenDeps = { "Services/Reserves/Sync", "Services/Reserves/Chat", "Database/DBOptions" },
        registryFromFeature = true,
        events = "-- events: emits ReservesDataChanged via addon.Bus",
    },
    {
        name = "Services/Reserves/Chat",
        path = "!KRT/Services/Reserves/Chat.lua",
        owner = "Chat",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Modules/Events", "Modules/Bus" },
        forbiddenDeps = { "Services/Raid", "Services/Chat" },
        registryFromFeature = true,
        events = "-- events: listens to wow.CHAT_MSG_WHISPER and replies with opt-in SoftRes summaries",
    },
}

local expectedDebugServices = {
    {
        name = "Services/Debug",
        path = "!KRT/Services/Debug.lua",
        owner = "module",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Time" },
        forbiddenDeps = { "Services/Raid", "Services/Rolls/Service" },
        registryFromFeature = true,
        events = "-- events: no direct bus events; publishes synthetic roster deltas through Services/Raid",
    },
}

local expectedMasterServices = {
    {
        name = "Services/Master/SoftRes",
        path = "!KRT/Services/Master/SoftRes.lua",
        owner = "SoftRes",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master SoftRes summary models",
    },
    {
        name = "Services/Master/SessionWinners",
        path = "!KRT/Services/Master/SessionWinners.lua",
        owner = "SessionWinners",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master session winner display models",
    },
    {
        name = "Services/Master/FlowState",
        path = "!KRT/Services/Master/FlowState.lua",
        owner = "FlowState",
        separator = ".",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Master/SoftRes",
            "Services/Master/SessionWinners",
        },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master workflow state models",
    },
    {
        name = "Services/Master/ButtonState",
        path = "!KRT/Services/Master/ButtonState.lua",
        owner = "ButtonState",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master button and tooltip state models",
    },
    {
        name = "Services/Master/RollRows",
        path = "!KRT/Services/Master/RollRows.lua",
        owner = "RollRows",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master roll row display models",
    },
    {
        name = "Services/Master/AssignmentCandidates",
        path = "!KRT/Services/Master/AssignmentCandidates.lua",
        owner = "AssignmentCandidates",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master assignment candidate row models",
    },
    {
        name = "Services/Master/AssignmentTargets",
        path = "!KRT/Services/Master/AssignmentTargets.lua",
        owner = "AssignmentTargets",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master assignment target row models",
    },
    {
        name = "Services/Master/DebugRaidGrid",
        path = "!KRT/Services/Master/DebugRaidGrid.lua",
        owner = "DebugRaidGrid",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master debug raid grid row models",
    },
    {
        name = "Services/Master/AwardMessages",
        path = "!KRT/Services/Master/AwardMessages.lua",
        owner = "AwardMessages",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master award chat message models",
    },
    {
        name = "Services/Master/LootSpam",
        path = "!KRT/Services/Master/LootSpam.lua",
        owner = "LootSpam",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master loot spam message models",
    },
    {
        name = "Services/Master/AwardCounter",
        path = "!KRT/Services/Master/AwardCounter.lua",
        owner = "AwardCounter",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master pending-award counter model helpers",
    },
    {
        name = "Services/Master/RollAnnouncements",
        path = "!KRT/Services/Master/RollAnnouncements.lua",
        owner = "RollAnnouncements",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: pure Master roll announcement message-plan service",
    },
    {
        name = "Services/Master/Service",
        path = "!KRT/Services/Master/Service.lua",
        owner = "Master",
        separator = ".",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Services/Master/SoftRes",
            "Services/Master/SessionWinners",
            "Services/Master/FlowState",
            "Services/Master/ButtonState",
            "Services/Master/RollRows",
            "Services/Master/AssignmentCandidates",
            "Services/Master/AssignmentTargets",
            "Services/Master/DebugRaidGrid",
            "Services/Master/AwardMessages",
            "Services/Master/LootSpam",
            "Services/Master/AwardCounter",
            "Services/Master/RollAnnouncements",
        },
        registryFromFeature = true,
        events = "-- events: none",
        note = "-- notes: Master service facade for focused domain/model helpers",
    },
}

local moduleTocPaths = {
    ["Modules/C"] = "Modules\\C.lua",
    ["Modules/Timer"] = "Modules\\Timer.lua",
    ["Modules/Events"] = "Modules\\Events.lua",
    ["Modules/Bus"] = "Modules\\Bus.lua",
    ["Modules/Comms"] = "Modules\\Comms.lua",
    ["Modules/Item"] = "Modules\\Item.lua",
    ["Modules/Strings"] = "Modules\\Strings.lua",
    ["Modules/LootSourceCandidates"] = "Modules\\LootSourceCandidates.lua",
    ["Modules/Time"] = "Modules\\Time.lua",
    ["Modules/Base64"] = "Modules\\Base64.lua",
    ["Modules/Json"] = "Modules\\Json.lua",
    ["Modules/Sort"] = "Modules\\Sort.lua",
    ["Modules/Dataset/IgnoredMobs"] = "Modules\\Dataset\\IgnoredMobs.lua",
    ["Modules/Dataset/LootSourcesData"] = "Modules\\Dataset\\LootSourcesData.lua",
    ["Modules/LootSources"] = "Modules\\LootSources.lua",
    ["Modules/Dataset/IgnoredItems"] = "Modules\\Dataset\\IgnoredItems.lua",
    ["Modules/ModuleRegistry"] = "Modules\\ModuleRegistry.lua",
    ["Services/Loot/Context"] = "Services\\Loot\\Context.lua",
    ["Services/Loot/State"] = "Services\\Loot\\State.lua",
    ["Services/Loot/Snapshots"] = "Services\\Loot\\Snapshots.lua",
    ["Services/Loot/PendingAwards"] = "Services\\Loot\\PendingAwards.lua",
    ["Services/Loot/PassiveGroupLoot"] = "Services\\Loot\\PassiveGroupLoot.lua",
    ["Services/Loot/Tracking"] = "Services\\Loot\\Tracking.lua",
    ["Services/Loot/Workflow"] = "Services\\Loot\\Workflow.lua",
    ["Services/Loot/Receipts"] = "Services\\Loot\\Receipts.lua",
    ["Services/Loot/Records"] = "Services\\Loot\\Records.lua",
    ["Services/Loot/Reconcile"] = "Services\\Loot\\Reconcile.lua",
    ["Services/Loot/Rules"] = "Services\\Loot\\Rules.lua",
    ["Services/Loot/DistributionSession"] = "Services\\Loot\\DistributionSession.lua",
    ["Services/Loot/Service"] = "Services\\Loot\\Service.lua",
    ["Services/Raid/State"] = "Services\\Raid\\State.lua",
    ["Services/Raid/Capabilities"] = "Services\\Raid\\Capabilities.lua",
    ["Services/Raid/Counts"] = "Services\\Raid\\Counts.lua",
    ["Services/Raid/Roster"] = "Services\\Raid\\Roster.lua",
    ["Services/Raid/Attendance"] = "Services\\Raid\\Attendance.lua",
    ["Services/Raid/LootRecords"] = "Services\\Raid\\LootRecords.lua",
    ["Services/Raid/Session"] = "Services\\Raid\\Session.lua",
    ["Services/Raid/LootMethod"] = "Services\\Raid\\LootMethod.lua",
    ["Services/Logger/Store"] = "Services\\Logger\\Store.lua",
    ["Services/Logger/View"] = "Services\\Logger\\View.lua",
    ["Services/Logger/Export"] = "Services\\Logger\\Export.lua",
    ["Services/Logger/Helpers"] = "Services\\Logger\\Helpers.lua",
    ["Services/Logger/Actions"] = "Services\\Logger\\Actions.lua",
    ["Controllers/Logger"] = "Controllers\\Logger.lua",
    ["Services/Reserves/Import"] = "Services\\Reserves\\Import.lua",
    ["Services/Reserves/Aliases"] = "Services\\Reserves\\Aliases.lua",
    ["Services/Reserves/Display"] = "Services\\Reserves\\Display.lua",
    ["Services/Reserves/Sync"] = "Services\\Reserves\\Sync.lua",
    ["Services/Reserves"] = "Services\\Reserves.lua",
    ["Services/Reserves/Chat"] = "Services\\Reserves\\Chat.lua",
    ["Widgets/ReservesUI"] = "Widgets\\ReservesUI.lua",
    ["Services/Debug"] = "Services\\Debug.lua",
    ["Services/Master/SoftRes"] = "Services\\Master\\SoftRes.lua",
    ["Services/Master/SessionWinners"] = "Services\\Master\\SessionWinners.lua",
    ["Services/Master/FlowState"] = "Services\\Master\\FlowState.lua",
    ["Services/Master/ButtonState"] = "Services\\Master\\ButtonState.lua",
    ["Services/Master/RollRows"] = "Services\\Master\\RollRows.lua",
    ["Services/Master/AssignmentCandidates"] = "Services\\Master\\AssignmentCandidates.lua",
    ["Services/Master/AssignmentTargets"] = "Services\\Master\\AssignmentTargets.lua",
    ["Services/Master/DebugRaidGrid"] = "Services\\Master\\DebugRaidGrid.lua",
    ["Services/Master/AwardMessages"] = "Services\\Master\\AwardMessages.lua",
    ["Services/Master/LootSpam"] = "Services\\Master\\LootSpam.lua",
    ["Services/Master/AwardCounter"] = "Services\\Master\\AwardCounter.lua",
    ["Services/Master/RollAnnouncements"] = "Services\\Master\\RollAnnouncements.lua",
    ["Services/Master/Service"] = "Services\\Master\\Service.lua",
    ["Services/Spammer/Draft"] = "Services\\Spammer\\Draft.lua",
    ["Services/Warnings/Store"] = "Services\\Warnings\\Store.lua",
}

local toc = read("!KRT/!KRT.toc")
assertBefore(toc, "Modules\\ModuleRegistry.lua", "Services\\Chat.lua")
assertBefore(toc, "Services\\Chat.lua", "Services\\Rolls\\Countdown.lua")
assertBefore(toc, "Services\\Rolls\\Countdown.lua", "Services\\Rolls\\Service.lua")
assertBefore(toc, "Services\\Rolls\\Sessions.lua", "Services\\Rolls\\Service.lua")
assertBefore(toc, "Services\\Rolls\\History.lua", "Services\\Rolls\\Service.lua")
assertBefore(toc, "Services\\Rolls\\Responses.lua", "Services\\Rolls\\Strategies.lua")
assertBefore(toc, "Services\\Rolls\\Strategies.lua", "Services\\Rolls\\Resolution.lua")
assertBefore(toc, "Services\\Rolls\\Strategies.lua", "Services\\Rolls\\Service.lua")
assertBefore(toc, "Services\\Rolls\\Responses.lua", "Services\\Rolls\\Display.lua")
assertBefore(toc, "Services\\Rolls\\Resolution.lua", "Services\\Rolls\\Display.lua")
assertBefore(toc, "Services\\Rolls\\Display.lua", "Services\\Rolls\\Service.lua")
assertBefore(toc, "Services\\Loot\\Context.lua", "Services\\Loot\\State.lua")
assertBefore(toc, "Services\\Loot\\Context.lua", "Services\\Loot\\Snapshots.lua")
assertBefore(toc, "Services\\Loot\\Context.lua", "Services\\Loot\\Tracking.lua")
assertBefore(toc, "Services\\Loot\\Context.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\State.lua", "Services\\Loot\\Snapshots.lua")
assertBefore(toc, "Services\\Loot\\PendingAwards.lua", "Services\\Loot\\Tracking.lua")
assertBefore(toc, "Services\\Loot\\PendingAwards.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\PassiveGroupLoot.lua", "Services\\Loot\\Tracking.lua")
assertBefore(toc, "Services\\Loot\\PassiveGroupLoot.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Tracking.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Workflow.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Receipts.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Records.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Reconcile.lua", "Services\\Loot\\Service.lua")
assertBefore(toc, "Services\\Loot\\Context.lua", "Services\\Raid\\State.lua")
assertBefore(toc, "Services\\Loot\\State.lua", "Services\\Raid\\State.lua")
assertBefore(toc, "Services\\Loot\\Snapshots.lua", "Services\\Raid\\State.lua")
assertBefore(toc, "Services\\Raid\\Counts.lua", "Services\\Raid\\LootRecords.lua")
assertBefore(toc, "Modules\\Timer.lua", "Services\\Raid\\Roster.lua")
assertBefore(toc, "Modules\\Bus.lua", "Services\\Raid\\Attendance.lua")

for i = 1, #expectedRaidServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedRaidServices[i].name])
end
for i = 1, #expectedLoggerServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedLoggerServices[i].name])
end
for i = 1, #expectedReservesServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedReservesServices[i].name])
end
for i = 1, #expectedDebugServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedDebugServices[i].name])
end
for i = 1, #expectedMasterServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedMasterServices[i].name])
end
for i = 1, #expectedSpammerServices do
    assertBefore(toc, "Modules\\ModuleRegistry.lua", moduleTocPaths[expectedSpammerServices[i].name])
end

local namespaceOptionFiles = {
    "!KRT/Services/Chat.lua",
    "!KRT/Services/Debug.lua",
    "!KRT/Services/Loot/Service.lua",
    "!KRT/Services/Rolls/Responses.lua",
    "!KRT/Services/Rolls/Service.lua",
    "!KRT/Services/Reserves.lua",
    "!KRT/Services/Reserves/Chat.lua",
}

for i = 1, #namespaceOptionFiles do
    assertNoLegacyOptionsProxy(namespaceOptionFiles[i])
end

local currentRaidDependencyFiles = {
    "!KRT/Services/Rolls/Service.lua",
    "!KRT/Services/Reserves.lua",
}
for i = 1, #currentRaidDependencyFiles do
    assertNoRootCurrentRaidLookup(currentRaidDependencyFiles[i])
end

assertNoRootDependencyLookup("!KRT/Services/Loot/Service.lua", "local services = addon.Services", "Services")
assertNoRootDependencyLookup("!KRT/Services/Raid/State.lua", "addon.Services and addon.Services.Loot", "Services")
assertNoRootDependencyLookup("!KRT/Services/Loot/Context.lua", "local core = addon.Database", "Database")
assertNoRootDependencyLookup("!KRT/Services/Reserves/Import.lua", "feature.Base64 or addon.Base64", "Base64")
assertNoRootDependencyLookup("!KRT/Services/Reserves/Import.lua", "feature.Json or addon.Json", "Json")
assertNoRootDependencyLookup("!KRT/Services/Logger/Actions.lua", "feature.LootSources or addon.LootSources", "LootSources")
assertNoRootDependencyLookup("!KRT/Services/Logger/Actions.lua", "addon.Services.Logger.Helpers.FindLootByItemId", "Helpers")
assertNoRootDependencyLookup("!KRT/Services/Raid/State.lua", "addon.LootSources or feature.LootSources", "LootSources")

local reservesChatSource = read("!KRT/Services/Reserves/Chat.lua")
assert(countPlain(reservesChatSource, "-- ----- Private helpers ----- --") == 1, "Services/Reserves/Chat must keep a single canonical private-helper section marker")

local raidStateSource = read("!KRT/Services/Raid/State.lua")
assertContains(raidStateSource, "local GetGroupTypeAndCount = feature.GetGroupTypeAndCount", "Services/Raid/State must localize group type helper from feature shared")
assertNotContains(raidStateSource, "local GetGroupTypeAndCount = addon.GetGroupTypeAndCount", "Services/Raid/State must not read group type helper directly from addon root")
assertNotContains(raidStateSource, "addon.GetGroupTypeAndCount()", "Services/Raid/State must call local GetGroupTypeAndCount dependency")
assertContains(raidStateSource, "local BossIDs = feature.BossIDs", "Services/Raid/State must localize BossIDs from feature shared")
assertContains(raidStateSource, "local GetCreatureId = feature.GetCreatureId", "Services/Raid/State must localize GetCreatureId from feature shared")
assertNotContains(raidStateSource, "addon.BossIDs", "Services/Raid/State must not read BossIDs directly from addon root")
assertNotContains(raidStateSource, "addon.GetCreatureId", "Services/Raid/State must not read GetCreatureId directly from addon root")

local raidRosterSource = read("!KRT/Services/Raid/Roster.lua")
assertContains(raidRosterSource, "local coreState = feature.coreState", "Services/Raid/Roster must localize core state from feature shared")
assertNotContains(raidRosterSource, "addon.State and addon.State.debug", "Services/Raid/Roster must use local coreState for debug lookup")
assertNotContains(raidRosterSource, "addon.State and addon.State.selectedRaid", "Services/Raid/Roster must use local coreState for selected raid lookup")

local debugServiceSource = read("!KRT/Services/Debug.lua")
assertContains(debugServiceSource, "local coreState = feature.coreState", "Services/Debug must localize core state from feature shared")
assertNotContains(debugServiceSource, "addon.State = addon.State or {}", "Services/Debug must not re-bootstrap root State")
assertNotContains(debugServiceSource, "addon.State.debug", "Services/Debug must use local coreState for debug state")

local initSource = read("!KRT/Init.lua")
assertContains(initSource, "LootSources = addon.LootSources", "feature shared must expose LootSources")
assertContains(initSource, "Timer = addon.Timer", "feature shared must expose Timer")
assertContains(initSource, "GetClassColor = addon.GetClassColor", "feature shared must expose GetClassColor helper")
assertContains(initSource, "BossIDs = addon.BossIDs", "feature shared must expose BossIDs")
assertContains(initSource, "GetCreatureId = addon.GetCreatureId", "feature shared must expose GetCreatureId helper")

local timerDependencyFiles = {
    "!KRT/Services/Chat.lua",
    "!KRT/Services/Reserves.lua",
    "!KRT/Services/Rolls/Countdown.lua",
    "!KRT/Services/Raid/Roster.lua",
    "!KRT/Services/Loot/Service.lua",
    "!KRT/Database/DBSyncer.lua",
}
for i = 1, #timerDependencyFiles do
    local source = read(timerDependencyFiles[i])
    assertContains(source, "local Timer = feature.Timer", timerDependencyFiles[i] .. " must localize Timer from feature shared")
    assertNotContains(source, "addon.Timer", timerDependencyFiles[i] .. " must use the local Timer dependency")
end

assertNoRootDependencyLookup("!KRT/Services/Loot/State.lua", "addon.Time.GetCurrentTime", "Time")
assertNoRootDependencyLookup("!KRT/Services/Loot/State.lua", "addon.C.GROUP_LOOT_PENDING_AWARD_TTL_SECONDS", "C")
assertNoRootDependencyLookup("!KRT/Services/Loot/Snapshots.lua", "addon.Time.GetCurrentTime", "Time")
assertNoRootDependencyLookup("!KRT/Services/Loot/DistributionSession.lua", "feature.Comms or addon.Comms", "Comms")
assertNoRootDependencyLookup("!KRT/Services/Loot/Service.lua", "Item or addon.Item", "Item")

local deformatServiceFiles = {
    "!KRT/Services/Chat.lua",
    "!KRT/Services/Rolls/Service.lua",
    "!KRT/Services/Loot/PassiveGroupLoot.lua",
    "!KRT/Services/Loot/Service.lua",
}
for i = 1, #deformatServiceFiles do
    local path = deformatServiceFiles[i]
    local source = read(path)
    assertContains(source, "local Deformat = feature.Deformat", path .. " must localize Deformat from feature shared")
    assertNotContains(source, "addon.Deformat", path .. " must use local Deformat dependency")
end

local loggerNamespaceFiles = {
    "!KRT/Services/Logger/Store.lua",
    "!KRT/Services/Logger/View.lua",
    "!KRT/Services/Logger/Export.lua",
    "!KRT/Services/Logger/Helpers.lua",
    "!KRT/Services/Logger/Actions.lua",
}
for i = 1, #loggerNamespaceFiles do
    local source = read(loggerNamespaceFiles[i])
    assertContains(source, "local Services = feature.Services", loggerNamespaceFiles[i] .. " must localize Services from feature shared")
    assertContains(source, "local Logger = Services.Logger", loggerNamespaceFiles[i] .. " must localize Logger namespace from Services")
    assertNotContains(source, "= addon.Services.Logger", loggerNamespaceFiles[i] .. " must not localize Logger services from addon root")
    assertContains(source, "-- events: none", loggerNamespaceFiles[i] .. " must document concrete event ownership in the Lua contract")
    assertNotContains(source, "-- events: document inbound/outbound events in module body", loggerNamespaceFiles[i] .. " must not keep the generic event placeholder")
end

local reservesNamespaceFiles = {
    "!KRT/Services/Reserves.lua",
    "!KRT/Services/Reserves/Import.lua",
    "!KRT/Services/Reserves/Aliases.lua",
    "!KRT/Services/Reserves/Display.lua",
    "!KRT/Services/Reserves/Sync.lua",
    "!KRT/Services/Reserves/Chat.lua",
}
for i = 1, #reservesNamespaceFiles do
    local source = read(reservesNamespaceFiles[i])
    assertContains(source, "local Services = feature.Services", reservesNamespaceFiles[i] .. " must localize Services from feature shared")
    assertContains(source, "local Reserves = Services.Reserves", reservesNamespaceFiles[i] .. " must localize Reserves namespace from Services")
    assertContains(source, "local module = Reserves", reservesNamespaceFiles[i] .. " must bind module through the local Reserves namespace")
    assertNotContains(source, "local module = addon.Services.Reserves", reservesNamespaceFiles[i] .. " must not localize Reserves from addon root")
end

local reservesDisplaySource = read("!KRT/Services/Reserves/Display.lua")
assertContains(reservesDisplaySource, "local GetClassColor = feature.GetClassColor", "Services/Reserves/Display must localize GetClassColor from feature shared")
assertNotContains(reservesDisplaySource, "addon.GetClassColor", "Services/Reserves/Display must use the local GetClassColor dependency")

local rollsNamespaceFiles = {
    "!KRT/Services/Rolls/Countdown.lua",
    "!KRT/Services/Rolls/Sessions.lua",
    "!KRT/Services/Rolls/History.lua",
    "!KRT/Services/Rolls/Responses.lua",
    "!KRT/Services/Rolls/Strategies.lua",
    "!KRT/Services/Rolls/Resolution.lua",
    "!KRT/Services/Rolls/Display.lua",
    "!KRT/Services/Rolls/Service.lua",
}
for i = 1, #rollsNamespaceFiles do
    local source = read(rollsNamespaceFiles[i])
    assertContains(source, "local Services = feature.Services", rollsNamespaceFiles[i] .. " must localize Services from feature shared")
    assertContains(source, "local Rolls = Services.Rolls", rollsNamespaceFiles[i] .. " must localize Rolls namespace from Services")
    assertContains(source, "local module = Rolls", rollsNamespaceFiles[i] .. " must bind module through the local Rolls namespace")
    assertNotContains(source, "local module = addon.Services.Rolls", rollsNamespaceFiles[i] .. " must not localize Rolls from addon root")
end

local lootNamespaceFiles = {
    "!KRT/Services/Loot/Context.lua",
    "!KRT/Services/Loot/State.lua",
    "!KRT/Services/Loot/Snapshots.lua",
    "!KRT/Services/Loot/PendingAwards.lua",
    "!KRT/Services/Loot/PassiveGroupLoot.lua",
    "!KRT/Services/Loot/Tracking.lua",
    "!KRT/Services/Loot/Workflow.lua",
    "!KRT/Services/Loot/Receipts.lua",
    "!KRT/Services/Loot/Records.lua",
    "!KRT/Services/Loot/Reconcile.lua",
    "!KRT/Services/Loot/Rules.lua",
    "!KRT/Services/Loot/DistributionSession.lua",
    "!KRT/Services/Loot/Service.lua",
}
for i = 1, #lootNamespaceFiles do
    local source = read(lootNamespaceFiles[i])
    assertContains(source, "local Services = feature.Services", lootNamespaceFiles[i] .. " must localize Services from feature shared")
    assertContains(source, "local Loot = Services.Loot", lootNamespaceFiles[i] .. " must localize Loot namespace from Services")
    assertContains(source, "local module = Loot", lootNamespaceFiles[i] .. " must bind module through the local Loot namespace")
    assertNotContains(source, "local module = addon.Services.Loot", lootNamespaceFiles[i] .. " must not localize Loot from addon root")
end

local raidNamespaceFiles = {
    "!KRT/Services/Raid/State.lua",
    "!KRT/Services/Raid/Capabilities.lua",
    "!KRT/Services/Raid/Counts.lua",
    "!KRT/Services/Raid/Roster.lua",
    "!KRT/Services/Raid/Attendance.lua",
    "!KRT/Services/Raid/LootRecords.lua",
    "!KRT/Services/Raid/Session.lua",
    "!KRT/Services/Raid/LootMethod.lua",
}
for i = 1, #raidNamespaceFiles do
    local source = read(raidNamespaceFiles[i])
    assertContains(source, "local Services = feature.Services", raidNamespaceFiles[i] .. " must localize Services from feature shared")
    assertContains(source, "local Raid = Services.Raid", raidNamespaceFiles[i] .. " must localize Raid namespace from Services")
    assertContains(source, "local module = Raid", raidNamespaceFiles[i] .. " must bind module through the local Raid namespace")
    assertNotContains(source, "local module = addon.Services.Raid", raidNamespaceFiles[i] .. " must not localize Raid from addon root")
end

local raidServiceEventHeaders = {
    {
        path = "!KRT/Services/Raid/State.lua",
        events = "-- events: emits RaidCreate",
    },
    {
        path = "!KRT/Services/Raid/Capabilities.lua",
        events = "-- events: none",
    },
    {
        path = "!KRT/Services/Raid/Counts.lua",
        events = "-- events: emits PlayerCountChanged",
    },
    {
        path = "!KRT/Services/Raid/Roster.lua",
        events = "-- events: emits RaidRosterDelta",
    },
    {
        path = "!KRT/Services/Raid/Attendance.lua",
        events = "-- events: consumes RaidRosterDelta",
    },
    {
        path = "!KRT/Services/Raid/LootRecords.lua",
        events = "-- events: none",
    },
    {
        path = "!KRT/Services/Raid/Session.lua",
        events = "-- events: none",
    },
}

for i = 1, #raidServiceEventHeaders do
    local spec = raidServiceEventHeaders[i]
    local source = read(spec.path)
    assertContains(source, spec.events, spec.path .. " must document concrete event ownership in the Lua contract")
    assertNotContains(source, "-- events: document inbound/outbound events in module body", spec.path .. " must not keep the generic event placeholder")
end

local singletonNamespaceFiles = {
    { path = "!KRT/Services/Chat.lua", namespace = "Chat" },
    { path = "!KRT/Services/Debug.lua", namespace = "Debug" },
}
for i = 1, #singletonNamespaceFiles do
    local expected = singletonNamespaceFiles[i]
    local source = read(expected.path)
    assertContains(source, "local Services = feature.Services", expected.path .. " must localize Services from feature shared")
    assertContains(source, "local module = Services." .. expected.namespace, expected.path .. " must bind module through the local Services namespace")
    assertNotContains(source, "local module = addon.Services." .. expected.namespace, expected.path .. " must not localize " .. expected.namespace .. " from addon root")
end

assertBefore(toc, "Modules\\Strings.lua", "Services\\Logger\\Store.lua")
assertBefore(toc, "Modules\\Sort.lua", "Services\\Logger\\View.lua")
assertBefore(toc, "Modules\\Base64.lua", "Services\\Logger\\Actions.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\View.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Export.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Helpers.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Actions.lua")
assertBefore(toc, "Services\\Logger\\Helpers.lua", "Services\\Logger\\View.lua")
assertBefore(toc, "Services\\Logger\\Helpers.lua", "Services\\Logger\\Actions.lua")
for i = 1, #expectedLoggerServices do
    assertBefore(toc, moduleTocPaths[expectedLoggerServices[i].name], "Controllers\\Logger.lua")
end

assertBefore(toc, "Services\\Reserves\\Import.lua", "Services\\Reserves.lua")
assertBefore(toc, "Services\\Reserves\\Display.lua", "Services\\Reserves.lua")
assertBefore(toc, "Services\\Reserves.lua", "Services\\Reserves\\Chat.lua")
assertBefore(toc, "Services\\Reserves.lua", "Widgets\\ReservesUI.lua")
assertBefore(toc, "Services\\Rolls\\Service.lua", "Services\\Debug.lua")
assertBefore(toc, "Services\\Raid\\Session.lua", "Services\\Debug.lua")
assertBefore(toc, "Services\\Master\\SoftRes.lua", "Services\\Master\\FlowState.lua")
assertBefore(toc, "Services\\Master\\SessionWinners.lua", "Services\\Master\\FlowState.lua")
assertBefore(toc, "Services\\Master\\SoftRes.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\SessionWinners.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\FlowState.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\ButtonState.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\RollRows.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\AssignmentCandidates.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\AssignmentTargets.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\DebugRaidGrid.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\AwardMessages.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\LootSpam.lua", "Services\\Master\\Service.lua")
assertBefore(toc, "Services\\Master\\Service.lua", "Widgets\\RaidGrid.lua")
assertBefore(toc, "Services\\Master\\Service.lua", "Controllers\\Master.lua")

for i = 1, #expectedLootServices do
    local expected = expectedLootServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedRaidServices do
    local expected = expectedRaidServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedLoggerServices do
    local expected = expectedLoggerServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedReservesServices do
    local expected = expectedReservesServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedDebugServices do
    local expected = expectedDebugServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedMasterServices do
    local expected = expectedMasterServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

for i = 1, #expectedSpammerServices do
    local expected = expectedSpammerServices[i]
    local expectedTocPath = moduleTocPaths[expected.name]
    for j = 1, #expected.deps do
        local depTocPath = moduleTocPaths[expected.deps[j]]
        if depTocPath then
            assertBefore(toc, depTocPath, expectedTocPath)
        end
    end
end

local source = read(expectedService.path)
local metadataStart = source:find('registry.AddModule("' .. expectedService.name .. '"', 1, true)
local lastPublicMethod = findLastExportedFunction(source, expectedService.owner, expectedService.separator)

assertContains(source, "local registry = feature.ModuleRegistry", "Services/Chat must localize ModuleRegistry from feature shared")
assertContains(source, expectedService.events, "Services/Chat must document concrete event ownership in the Lua contract")
assertNotContains(source, "-- events: document inbound/outbound events in module body", "Services/Chat must not keep the generic event placeholder")
assertNotContains(source, "local registry = addon.ModuleRegistry", "Services/Chat must not read ModuleRegistry directly from addon root")
local sharedHelperSource = read("!KRT/Init.lua")
assertContains(sharedHelperSource, "GetGroupTypeAndCount = addon.GetGroupTypeAndCount", "feature shared contract must expose group type helper")
assertContains(source, "local GetGroupTypeAndCount = feature.GetGroupTypeAndCount", "Services/Chat must localize group type helper from feature shared")
assertContains(source, "local UnitIsGroupLeader = feature.UnitIsGroupLeader", "Services/Chat must localize group leader helper from feature shared")
assertContains(source, "local UnitIsGroupAssistant = feature.UnitIsGroupAssistant", "Services/Chat must localize group assistant helper from feature shared")
assertNotContains(source, "local UnitIsGroupLeader = feature.UnitIsGroupLeader or addon.UnitIsGroupLeader", "Services/Chat must not fall back to addon root group leader helper")
assertNotContains(
    source,
    "local UnitIsGroupAssistant = feature.UnitIsGroupAssistant or addon.UnitIsGroupAssistant",
    "Services/Chat must not fall back to addon root group assistant helper"
)
assertNotContains(source, "local GetGroupTypeAndCount = addon.GetGroupTypeAndCount", "Services/Chat must not read group type helper directly from addon root")
assertNotContains(source, "addon.GetGroupTypeAndCount()", "Services/Chat must call local GetGroupTypeAndCount dependency")
assertNotContains(source, "local leaderFn = addon.UnitIsGroupLeader", "Services/Chat must use local UnitIsGroupLeader dependency")
assertNotContains(source, "local assistantFn = addon.UnitIsGroupAssistant", "Services/Chat must use local UnitIsGroupAssistant dependency")
assertContains(source, 'registry.AddModule("Services/Chat"', "Services/Chat must direct-register module metadata")
assertContains(source, 'registry.SetLoaded("Services/Chat")', "Services/Chat must mark direct registry module loaded")
assertNotContains(source, "ModuleRegistryPendingRegistrations", "Services/Chat must not use pending fallback")
assert(lastPublicMethod, "Services/Chat must expose public methods before registry metadata")
assert(lastPublicMethod < metadataStart, "Services/Chat registry metadata must appear after its last public method")

local serviceDeps = getPostRegistryDeps(source, expectedService.name)
assertDeps(serviceDeps, expectedService.deps, expectedService.name)
for i = 1, #serviceDeps do
    assert(serviceDeps[i] ~= "Services/Raid", "Services/Chat must not hard-depend on Services/Raid")
    assert(serviceDeps[i]:match("^Controllers/") == nil, "Services/Chat must not depend on Controllers")
    assert(serviceDeps[i]:match("^Widgets/") == nil, "Services/Chat must not depend on Widgets")
end

for i = 1, #expectedRollServices do
    local expected = expectedRollServices[i]
    local rollSource = read(expected.path)
    local rollMetadataStart = rollSource:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local lastExportedFunction = findLastExportedFunction(rollSource, expected.owner, expected.separator)
    local deps = getPostRegistryDeps(rollSource, expected.name)

    assertContains(rollSource, "local registry = feature.ModuleRegistry", expected.name .. " must localize ModuleRegistry from feature shared")
    if expected.note then
        assertContains(rollSource, "-- shared: local feature = addon.Database.GetFeatureShared()", expected.name .. " must document its feature shared header dependency")
        assertContains(rollSource, expected.note, expected.name .. " must document its helper role as a note")
    end
    assertContains(rollSource, expected.events, expected.name .. " must document its KRT Lua Contract events")
    assertNotContains(rollSource, "local registry = addon.ModuleRegistry", expected.name .. " must not read ModuleRegistry directly from addon root")
    assertContains(rollSource, 'registry.AddModule("' .. expected.name .. '"', expected.name .. " must direct-register module metadata")
    assertContains(rollSource, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark direct registry module loaded")
    assertNotContains(rollSource, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")
    assert(lastExportedFunction, expected.name .. " must expose public helpers before registry metadata")
    assert(lastExportedFunction < rollMetadataStart, expected.name .. " registry metadata must appear after its last public helper")

    assertDeps(deps, expected.deps, expected.name)
    for j = 1, #deps do
        assert(deps[j]:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
        assert(deps[j]:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
    end
    if expected.forbiddenDeps then
        for j = 1, #expected.forbiddenDeps do
            local forbidden = expected.forbiddenDeps[j]
            for k = 1, #deps do
                assert(deps[k] ~= forbidden, expected.name .. " must not hard-depend on " .. forbidden)
            end
        end
    end
end

for i = 1, #expectedLootServices do
    local expected = expectedLootServices[i]
    local lootSource = read(expected.path)
    local lootMetadataStart = lootSource:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local lastExportedFunction = findLastExportedFunctionAny(lootSource, expected.owners)
    local deps = getPostRegistryDeps(lootSource, expected.name)

    assertContains(lootSource, "local registry = feature.ModuleRegistry", expected.name .. " must localize ModuleRegistry from feature shared")
    assertContains(lootSource, expected.events, expected.name .. " must document its KRT Lua Contract events")
    if expected.note then
        assertContains(lootSource, "-- shared: local feature = addon.Database.GetFeatureShared()", expected.name .. " must document its feature shared header dependency")
        assertContains(lootSource, expected.note, expected.name .. " must document its helper role as a note")
    end
    assertNotContains(lootSource, "local registry = addon.ModuleRegistry", expected.name .. " must not read ModuleRegistry directly from addon root")
    assertContains(lootSource, 'registry.AddModule("' .. expected.name .. '"', expected.name .. " must direct-register module metadata")
    assertContains(lootSource, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark direct registry module loaded")
    assertNotContains(lootSource, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")
    assert(lastExportedFunction, expected.name .. " must expose public helpers before registry metadata")
    assert(lastExportedFunction < lootMetadataStart, expected.name .. " registry metadata must appear after its last public helper")

    assertDeps(deps, expected.deps, expected.name)
    for j = 1, #deps do
        assert(deps[j]:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
        assert(deps[j]:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
    end
    if expected.forbiddenDeps then
        for j = 1, #expected.forbiddenDeps do
            local forbidden = expected.forbiddenDeps[j]
            for k = 1, #deps do
                assert(deps[k] ~= forbidden, expected.name .. " must not hard-depend on " .. forbidden)
            end
        end
    end
end

for i = 1, #expectedRaidServices do
    local expected = expectedRaidServices[i]
    local raidSource = read(expected.path)
    local raidMetadataStart = raidSource:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local lastExportedFunction = findLastExportedFunctionAny(raidSource, expected.owners)
    local deps = getPostRegistryDeps(raidSource, expected.name)

    assertContains(raidSource, "local registry = feature.ModuleRegistry", expected.name .. " must localize ModuleRegistry from feature shared")
    assertNotContains(raidSource, "local registry = addon.ModuleRegistry", expected.name .. " must not read ModuleRegistry directly from addon root")
    assertContains(raidSource, 'registry.AddModule("' .. expected.name .. '"', expected.name .. " must direct-register module metadata")
    assertContains(raidSource, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark direct registry module loaded")
    assertNotContains(raidSource, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")
    assert(lastExportedFunction, expected.name .. " must expose public helpers before registry metadata")
    assert(lastExportedFunction < raidMetadataStart, expected.name .. " registry metadata must appear after its last public helper")

    assertDeps(deps, expected.deps, expected.name)
    for j = 1, #deps do
        assert(deps[j]:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
        assert(deps[j]:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
    end
    if expected.forbiddenDeps then
        for j = 1, #expected.forbiddenDeps do
            local forbidden = expected.forbiddenDeps[j]
            for k = 1, #deps do
                assert(deps[k] ~= forbidden, expected.name .. " must not hard-depend on " .. forbidden)
            end
        end
    end
end

local function assertServiceRegistryContract(expected)
    local expectedSource = read(expected.path)
    local expectedMetadataStart = expectedSource:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local publicApiStart = findExpectedPublicApi(expectedSource, expected)
    local deps = getPostRegistryDeps(expectedSource, expected.name)

    if expected.registryFromFeature then
        assertContains(expectedSource, "local registry = feature.ModuleRegistry", expected.name .. " must localize ModuleRegistry from feature shared")
        assertNotContains(expectedSource, "local registry = addon.ModuleRegistry", expected.name .. " must not read ModuleRegistry directly from addon root")
    else
        assertContains(expectedSource, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
    end
    if expected.events then
        assertContains(expectedSource, expected.events, expected.name .. " must document its KRT Lua Contract events")
    end
    if expected.note then
        assertContains(expectedSource, "-- shared: local feature = addon.Database.GetFeatureShared()", expected.name .. " must document its feature shared header dependency")
        assertContains(expectedSource, expected.note, expected.name .. " must document its helper role as a note")
    end
    assertContains(expectedSource, 'registry.AddModule("' .. expected.name .. '"', expected.name .. " must direct-register module metadata")
    assertContains(expectedSource, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark direct registry module loaded")
    assertNotContains(expectedSource, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")
    assert(publicApiStart, expected.name .. " must expose public helpers before registry metadata")
    assert(publicApiStart < expectedMetadataStart, expected.name .. " registry metadata must appear after its public API")

    assertDeps(deps, expected.deps, expected.name)
    for j = 1, #deps do
        assert(deps[j]:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
        assert(deps[j]:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
    end
    if expected.forbiddenDeps then
        for j = 1, #expected.forbiddenDeps do
            local forbidden = expected.forbiddenDeps[j]
            for k = 1, #deps do
                assert(deps[k] ~= forbidden, expected.name .. " must not hard-depend on " .. forbidden)
            end
        end
    end
end

for i = 1, #expectedLoggerServices do
    assertServiceRegistryContract(expectedLoggerServices[i])
end

for i = 1, #expectedReservesServices do
    assertServiceRegistryContract(expectedReservesServices[i])
end

for i = 1, #expectedDebugServices do
    assertServiceRegistryContract(expectedDebugServices[i])
end

for i = 1, #expectedMasterServices do
    assertServiceRegistryContract(expectedMasterServices[i])
end

for i = 1, #expectedSpammerServices do
    assertServiceRegistryContract(expectedSpammerServices[i])
end

assertServiceRegistryContract(expectedSpecInspectService)

local pending = {}
for i = 1, #preRegistryCoreModules do
    local expected = preRegistryCoreModules[i]
    pending[#pending + 1] = {
        name = expected.name,
        deps = expected.deps,
        loaded = true,
    }
end
for i = 1, #preRegistryUtilityModules do
    local expected = preRegistryUtilityModules[i]
    pending[#pending + 1] = {
        name = expected.name,
        deps = expected.deps,
        loaded = true,
    }
end

local addon = {
    Database = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
    ModuleRegistryPendingRegistrations = pending,
}

local chunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
chunk("!KRT", addon)

local registry = addon.ModuleRegistry
assert(#addon.ModuleRegistryPendingRegistrations == 0, "ModuleRegistry must clear consumed pending registrations")

for i = 1, #directRegistryModules do
    local expected = directRegistryModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

for i = 1, #postRegistryCoreModules do
    local expected = postRegistryCoreModules[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

registry.AddModule(expectedService.name, { deps = expectedService.deps })
registry.SetLoaded(expectedService.name)

for i = 1, #expectedLootServices do
    local expected = expectedLootServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

for i = 1, #expectedRaidServices do
    local expected = expectedRaidServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

registry.AddModule(expectedSpecInspectService.name, { deps = expectedSpecInspectService.deps })
registry.SetLoaded(expectedSpecInspectService.name)

for i = 1, #expectedRollServices do
    local expected = expectedRollServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end
for i = 1, #expectedDebugServices do
    local expected = expectedDebugServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end
for i = 1, #expectedReservesServices do
    local expected = expectedReservesServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end
for i = 1, #expectedLoggerServices do
    local expected = expectedLoggerServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end
for i = 1, #expectedMasterServices do
    local expected = expectedMasterServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end
for i = 1, #expectedSpammerServices do
    local expected = expectedSpammerServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

local ok, issues = registry.GetLoadOrderStatus()
if not ok then
    local issue = issues and issues[1] or {}
    error("services registry load order must validate; first issue=" .. tostring(issue.module) .. " -> " .. tostring(issue.dependency) .. " (" .. tostring(issue.reason) .. ")")
end
assert(issues == nil, "valid services registry sequence must not report dependency issues")

local status = registry.GetStatus(expectedService.name)
assert(status and status.Loaded == true, "Services/Chat must be loaded in registry")
assertDeps(status.Deps, expectedService.deps, expectedService.name)

local specInspectStatus = registry.GetStatus(expectedSpecInspectService.name)
assert(specInspectStatus and specInspectStatus.Loaded == true, "Services/SpecInspect must be loaded in registry")
assertDeps(specInspectStatus.Deps, expectedSpecInspectService.deps, expectedSpecInspectService.name)

for i = 1, #expectedRollServices do
    local expected = expectedRollServices[i]
    local rollStatus = registry.GetStatus(expected.name)
    assert(rollStatus and rollStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(rollStatus.Deps, expected.deps, expected.name)
end

for i = 1, #expectedLootServices do
    local expected = expectedLootServices[i]
    local lootStatus = registry.GetStatus(expected.name)
    assert(lootStatus and lootStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(lootStatus.Deps, expected.deps, expected.name)
end

for i = 1, #expectedRaidServices do
    local expected = expectedRaidServices[i]
    local raidStatus = registry.GetStatus(expected.name)
    assert(raidStatus and raidStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(raidStatus.Deps, expected.deps, expected.name)
end
for i = 1, #expectedDebugServices do
    local expected = expectedDebugServices[i]
    local debugStatus = registry.GetStatus(expected.name)
    assert(debugStatus and debugStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(debugStatus.Deps, expected.deps, expected.name)
end
for i = 1, #expectedReservesServices do
    local expected = expectedReservesServices[i]
    local reservesStatus = registry.GetStatus(expected.name)
    assert(reservesStatus and reservesStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(reservesStatus.Deps, expected.deps, expected.name)
end
for i = 1, #expectedLoggerServices do
    local expected = expectedLoggerServices[i]
    local loggerStatus = registry.GetStatus(expected.name)
    assert(loggerStatus and loggerStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(loggerStatus.Deps, expected.deps, expected.name)
end
for i = 1, #expectedMasterServices do
    local expected = expectedMasterServices[i]
    local masterStatus = registry.GetStatus(expected.name)
    assert(masterStatus and masterStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(masterStatus.Deps, expected.deps, expected.name)
end

for i = 1, #expectedSpammerServices do
    local expected = expectedSpammerServices[i]
    local spammerStatus = registry.GetStatus(expected.name)
    assert(spammerStatus and spammerStatus.Loaded == true, expected.name .. " must be loaded in registry")
    assertDeps(spammerStatus.Deps, expected.deps, expected.name)
end

local negativeAddon = {
    Database = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
    ModuleRegistryPendingRegistrations = pending,
}

local negativeChunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(negativeChunk, setmetatable({ select = select }, { __index = _G }))
negativeChunk("!KRT", negativeAddon)

local negativeRegistry = negativeAddon.ModuleRegistry
negativeRegistry.AddModule("Services/Loot/Service", { deps = expectedLootServices[#expectedLootServices].deps })
negativeRegistry.SetLoaded("Services/Loot/Service")
negativeRegistry.AddModule("Services/Loot/Tracking", { deps = expectedLootServices[6].deps })
negativeRegistry.SetLoaded("Services/Loot/Tracking")

local negativeOk, negativeIssues = negativeRegistry.GetLoadOrderStatus()
assert(not negativeOk, "out-of-order Loot service registry sequence must fail validation")

local foundOutOfOrder = false
for i = 1, #(negativeIssues or {}) do
    local issue = negativeIssues[i]
    if issue.module == "Services/Loot/Service" and issue.dependency == "Services/Loot/Tracking" and issue.reason == "out_of_order" then
        foundOutOfOrder = true
        break
    end
end
assert(foundOutOfOrder, "Services/Loot/Service before Services/Loot/Tracking must report out_of_order")

local raidNegativeAddon = {
    Database = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
}

local raidNegativeChunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(raidNegativeChunk, setmetatable({ select = select }, { __index = _G }))
raidNegativeChunk("!KRT", raidNegativeAddon)

local raidNegativeRegistry = raidNegativeAddon.ModuleRegistry
raidNegativeRegistry.AddModule("Services/Raid/LootRecords", { deps = expectedRaidServices[6].deps })
raidNegativeRegistry.SetLoaded("Services/Raid/LootRecords")
raidNegativeRegistry.AddModule("Services/Raid/Counts", { deps = expectedRaidServices[3].deps })
raidNegativeRegistry.SetLoaded("Services/Raid/Counts")

local raidNegativeOk, raidNegativeIssues = raidNegativeRegistry.GetLoadOrderStatus()
assert(not raidNegativeOk, "out-of-order Raid loot-record registry sequence must fail validation")

local foundRaidLootRecordsOutOfOrder = false
for i = 1, #(raidNegativeIssues or {}) do
    local issue = raidNegativeIssues[i]
    if issue.module == "Services/Raid/LootRecords" and issue.dependency == "Services/Raid/Counts" and issue.reason == "out_of_order" then
        foundRaidLootRecordsOutOfOrder = true
        break
    end
end
assert(foundRaidLootRecordsOutOfOrder, "Services/Raid/LootRecords before Services/Raid/Counts must report out_of_order")

local raidStateNegativeAddon = {
    Database = {
        GetFeatureShared = function()
            return {}
        end,
    },
    ModuleRegistryPendingLoads = { "Init" },
}

local raidStateNegativeChunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
setfenv(raidStateNegativeChunk, setmetatable({ select = select }, { __index = _G }))
raidStateNegativeChunk("!KRT", raidStateNegativeAddon)

local raidStateNegativeRegistry = raidStateNegativeAddon.ModuleRegistry
raidStateNegativeRegistry.AddModule("Services/Raid/State", { deps = expectedRaidServices[1].deps })
raidStateNegativeRegistry.SetLoaded("Services/Raid/State")
raidStateNegativeRegistry.AddModule("Services/Loot/Snapshots", { deps = expectedLootServices[3].deps })
raidStateNegativeRegistry.SetLoaded("Services/Loot/Snapshots")

local raidStateNegativeOk, raidStateNegativeIssues = raidStateNegativeRegistry.GetLoadOrderStatus()
assert(not raidStateNegativeOk, "out-of-order Raid state registry sequence must fail validation")

local foundRaidStateOutOfOrder = false
for i = 1, #(raidStateNegativeIssues or {}) do
    local issue = raidStateNegativeIssues[i]
    if issue.module == "Services/Raid/State" and issue.dependency == "Services/Loot/Snapshots" and issue.reason == "out_of_order" then
        foundRaidStateOutOfOrder = true
        break
    end
end
assert(foundRaidStateOutOfOrder, "Services/Raid/State before Services/Loot/Snapshots must report out_of_order")

local function findExpectedSpec(name)
    local expectedLists = {
        preRegistryUtilityModules,
        directRegistryModules,
        expectedRollServices,
        expectedLoggerServices,
        expectedReservesServices,
        expectedDebugServices,
        expectedMasterServices,
        { expectedSpecInspectService },
    }

    for i = 1, #expectedLists do
        local list = expectedLists[i]
        for j = 1, #list do
            if list[j].name == name then
                return list[j]
            end
        end
    end
    return nil
end

local function assertOutOfOrder(moduleName, dependencyName)
    local moduleSpec = assert(findExpectedSpec(moduleName), "missing expected spec: " .. moduleName)
    local dependencySpec = assert(findExpectedSpec(dependencyName), "missing expected spec: " .. dependencyName)
    local outOfOrderAddon = {
        Database = {
            GetFeatureShared = function()
                return {}
            end,
        },
        ModuleRegistryPendingLoads = { "Init" },
    }

    local outOfOrderChunk = assert(loadfile("!KRT/Modules/ModuleRegistry.lua"))
    setfenv(outOfOrderChunk, setmetatable({ select = select }, { __index = _G }))
    outOfOrderChunk("!KRT", outOfOrderAddon)

    local outOfOrderRegistry = outOfOrderAddon.ModuleRegistry
    outOfOrderRegistry.AddModule(moduleSpec.name, { deps = moduleSpec.deps })
    outOfOrderRegistry.SetLoaded(moduleSpec.name)
    outOfOrderRegistry.AddModule(dependencySpec.name, { deps = dependencySpec.deps })
    outOfOrderRegistry.SetLoaded(dependencySpec.name)

    local outOfOrderOk, outOfOrderIssues = outOfOrderRegistry.GetLoadOrderStatus()
    assert(not outOfOrderOk, moduleName .. " before " .. dependencyName .. " must fail validation")

    local found = false
    for i = 1, #(outOfOrderIssues or {}) do
        local issue = outOfOrderIssues[i]
        if issue.module == moduleName and issue.dependency == dependencyName and issue.reason == "out_of_order" then
            found = true
            break
        end
    end
    assert(found, moduleName .. " before " .. dependencyName .. " must report out_of_order")
end

assertOutOfOrder("Services/Logger/View", "Services/Logger/Store")
assertOutOfOrder("Services/Logger/Actions", "Services/Logger/Helpers")
assertOutOfOrder("Services/Rolls/Resolution", "Services/Rolls/Strategies")
assertOutOfOrder("Services/Reserves", "Services/Reserves/Import")
assertOutOfOrder("Services/Reserves", "Services/Reserves/Aliases")
assertOutOfOrder("Services/Reserves", "Services/Reserves/Display")
assertOutOfOrder("Services/Reserves/Sync", "Modules/Comms")
assertOutOfOrder("Services/Reserves/Chat", "Modules/Bus")
assertOutOfOrder("Services/Reserves/Chat", "Modules/Events")
assertOutOfOrder("Services/Debug", "Modules/Time")

print("module registry services source contract passed")
