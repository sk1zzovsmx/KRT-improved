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
    { name = "Core/DB", deps = { "Init" } },
    { name = "Core/Options", deps = { "Init" } },
    { name = "Core/DBSchema", deps = { "Init" } },
    { name = "Core/DBManager", deps = { "Init", "Core/DB" } },
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
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Visuals" } },
    { name = "Modules/UI/MultiSelect", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/Bus", deps = { "Init", "Modules/ModuleRegistry" } },
}

local postRegistryCoreModules = {
    {
        name = "Core/DBRaidMigrations",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBSchema", "Modules/Strings" },
    },
    {
        name = "Core/DBRaidStore",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Core/DB",
            "Core/DBSchema",
            "Core/DBRaidMigrations",
            "Modules/Time",
            "Modules/Strings",
        },
    },
    {
        name = "Core/DBRaidQueries",
        deps = { "Init", "Modules/ModuleRegistry", "Core/DB", "Core/DBRaidStore", "Modules/Sort" },
    },
    {
        name = "Core/DBRaidValidator",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Core/DB",
            "Core/DBSchema",
            "Core/DBRaidMigrations",
            "Core/DBRaidStore",
            "Modules/Dataset/IgnoredMobs",
        },
    },
    {
        name = "Core/DBSyncer",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Core/DB",
            "Core/DBSchema",
            "Core/DBRaidStore",
            "Core/DBRaidQueries",
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
}

local expectedRollServices = {
    {
        name = "Services/Rolls/Countdown",
        path = "!KRT/Services/Rolls/Countdown.lua",
        owner = "Countdown",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Timer", "Services/Chat" },
    },
    {
        name = "Services/Rolls/Sessions",
        path = "!KRT/Services/Rolls/Sessions.lua",
        owner = "Sessions",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Modules/Strings" },
    },
    {
        name = "Services/Rolls/History",
        path = "!KRT/Services/Rolls/History.lua",
        owner = "History",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus" },
    },
    {
        name = "Services/Rolls/Responses",
        path = "!KRT/Services/Rolls/Responses.lua",
        owner = "Responses",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Services/Chat" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves", "Services/Loot" },
    },
    {
        name = "Services/Rolls/Strategies",
        path = "!KRT/Services/Rolls/Strategies.lua",
        owner = "Strategies",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Services/Rolls/Resolution",
        path = "!KRT/Services/Rolls/Resolution.lua",
        owner = "Resolution",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Strategies" },
    },
    {
        name = "Services/Rolls/Display",
        path = "!KRT/Services/Rolls/Display.lua",
        owner = "Display",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Responses", "Services/Rolls/Resolution" },
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
        },
        forbiddenDeps = { "Services/Raid", "Services/Reserves", "Services/Loot" },
    },
}

local expectedLootServices = {
    {
        name = "Services/Loot/Context",
        path = "!KRT/Services/Loot/Context.lua",
        owners = { { owner = "LootContext", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry" },
    },
    {
        name = "Services/Loot/State",
        path = "!KRT/Services/Loot/State.lua",
        owners = {
            { owner = "ContextState", separator = "." },
            { owner = "Sessions", separator = "." },
        },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Services/Loot/Context" },
    },
    {
        name = "Services/Loot/Snapshots",
        path = "!KRT/Services/Loot/Snapshots.lua",
        owners = { { owner = "Snapshots", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Services/Loot/State", "Services/Loot/Context" },
    },
    {
        name = "Services/Loot/PendingAwards",
        path = "!KRT/Services/Loot/PendingAwards.lua",
        owners = { { owner = "PendingAwards", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item" },
    },
    {
        name = "Services/Loot/PassiveGroupLoot",
        path = "!KRT/Services/Loot/PassiveGroupLoot.lua",
        owners = { { owner = "PassiveGroupLoot", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Strings" },
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
    },
    {
        name = "Services/Loot/Workflow",
        path = "!KRT/Services/Loot/Workflow.lua",
        owners = { { owner = "Workflow", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Loot/Receipts",
        path = "!KRT/Services/Loot/Receipts.lua",
        owners = { { owner = "Receipts", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Loot/Records",
        path = "!KRT/Services/Loot/Records.lua",
        owners = { { owner = "Records", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Time" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Loot/Reconcile",
        path = "!KRT/Services/Loot/Reconcile.lua",
        owners = { { owner = "Reconcile", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Loot/Rules",
        path = "!KRT/Services/Loot/Rules.lua",
        owners = { { owner = "Rules", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Dataset/IgnoredItems" },
    },
    {
        name = "Services/Loot/DistributionSession",
        path = "!KRT/Services/Loot/DistributionSession.lua",
        owners = { { owner = "DistributionSession", separator = "." } },
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Comms", "Modules/Item" },
        forbiddenDeps = { "Services/Raid" },
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
            "Modules/Dataset/IgnoredItems",
            "Services/Loot/Context",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
            "Services/Loot/Tracking",
            "Services/Loot/Workflow",
            "Services/Loot/Receipts",
            "Services/Loot/Records",
            "Services/Loot/Reconcile",
        },
        forbiddenDeps = {
            "Services/Raid",
            "Services/Chat",
            "Services/Rolls/Service",
            "Services/Loot/Rules",
            "Services/Loot/DistributionSession",
        },
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
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Strings", "Services/Raid/Counts" },
    },
    {
        name = "Services/Raid/Session",
        path = "!KRT/Services/Raid/Session.lua",
        owners = { { owner = "module", separator = ":" } },
        deps = { "Init", "Modules/ModuleRegistry" },
    },
}

local expectedLoggerServices = {
    {
        name = "Services/Logger/Store",
        path = "!KRT/Services/Logger/Store.lua",
        owner = "Store",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Core/DBRaidQueries", "Core/DBRaidStore" },
    },
    {
        name = "Services/Logger/View",
        path = "!KRT/Services/Logger/View.lua",
        owner = "View",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Sort", "Services/Logger/Store" },
        forbiddenDeps = { "Services/Raid", "Core/DBRaidQueries", "Core/DBRaidStore" },
    },
    {
        name = "Services/Logger/Export",
        path = "!KRT/Services/Logger/Export.lua",
        owner = "Export",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Logger/Store" },
        forbiddenDeps = { "Services/Raid", "Core/DBRaidQueries", "Core/DBRaidStore" },
    },
    {
        name = "Services/Logger/Helpers",
        path = "!KRT/Services/Logger/Helpers.lua",
        owner = "Helpers",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Services/Logger/Store" },
        forbiddenDeps = { "Services/Raid", "Core/DBRaidQueries", "Core/DBRaidStore" },
    },
    {
        name = "Services/Logger/Actions",
        path = "!KRT/Services/Logger/Actions.lua",
        owner = "Actions",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Base64", "Services/Logger/Store", "Services/Logger/Helpers" },
        forbiddenDeps = { "Services/Raid", "Core/DBRaidQueries", "Core/DBRaidStore" },
    },
}

local expectedReservesServices = {
    {
        name = "Services/Reserves/Import",
        path = "!KRT/Services/Reserves/Import.lua",
        metadataAfterNeedle = "ParseImport = parseImport,",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Base64", "Modules/Json" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Reserves/Aliases",
        path = "!KRT/Services/Reserves/Aliases.lua",
        owner = "Aliases",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves" },
    },
    {
        name = "Services/Reserves/Display",
        path = "!KRT/Services/Reserves/Display.lua",
        owner = "Display",
        separator = ".",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid" },
    },
    {
        name = "Services/Reserves/Sync",
        path = "!KRT/Services/Reserves/Sync.lua",
        owner = "Sync",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Comms", "Modules/Strings" },
        forbiddenDeps = { "Services/Raid", "Services/Reserves" },
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
        forbiddenDeps = { "Services/Reserves/Sync", "Services/Reserves/Chat", "Core/Options" },
    },
    {
        name = "Services/Reserves/Chat",
        path = "!KRT/Services/Reserves/Chat.lua",
        owner = "Chat",
        separator = ":",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Modules/Events", "Modules/Bus" },
        forbiddenDeps = { "Services/Raid", "Services/Chat" },
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

assertBefore(toc, "Modules\\Strings.lua", "Services\\Logger\\Store.lua")
assertBefore(toc, "Modules\\Sort.lua", "Services\\Logger\\View.lua")
assertBefore(toc, "Modules\\Base64.lua", "Services\\Logger\\Actions.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\View.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Export.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Helpers.lua")
assertBefore(toc, "Services\\Logger\\Store.lua", "Services\\Logger\\Actions.lua")
assertBefore(toc, "Services\\Logger\\View.lua", "Services\\Logger\\Helpers.lua")
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

local source = read(expectedService.path)
local metadataStart = source:find('registry.AddModule("' .. expectedService.name .. '"', 1, true)
local lastPublicMethod = findLastExportedFunction(source, expectedService.owner, expectedService.separator)

assertContains(source, "local registry = addon.ModuleRegistry", "Services/Chat must use direct registry lookup")
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

    assertContains(rollSource, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
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

    assertContains(lootSource, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
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

    assertContains(raidSource, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
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

    assertContains(expectedSource, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
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
    Core = {
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

for i = 1, #expectedRollServices do
    local expected = expectedRollServices[i]
    registry.AddModule(expected.name, { deps = expected.deps })
    registry.SetLoaded(expected.name)
end

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

local ok, issues = registry.GetLoadOrderStatus()
if not ok then
    local issue = issues and issues[1] or {}
    error("services registry load order must validate; first issue=" .. tostring(issue.module) .. " -> " .. tostring(issue.dependency) .. " (" .. tostring(issue.reason) .. ")")
end
assert(issues == nil, "valid services registry sequence must not report dependency issues")

local status = registry.GetStatus(expectedService.name)
assert(status and status.Loaded == true, "Services/Chat must be loaded in registry")
assertDeps(status.Deps, expectedService.deps, expectedService.name)

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

local negativeAddon = {
    Core = {
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
    Core = {
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
    Core = {
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
        Core = {
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
