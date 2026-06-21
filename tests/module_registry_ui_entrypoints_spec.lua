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

local function getPostRegistryDeps(source, moduleName)
    local registerStart = source:find('registry.AddModule("' .. moduleName .. '"', 1, true)
    assert(registerStart, moduleName .. " must direct-register dependency metadata")
    local depsStart = source:find("deps = {", registerStart, true)
    assert(depsStart, moduleName .. " must declare direct-register deps")
    local depsEnd = source:find("}", depsStart, true)
    assert(depsEnd, moduleName .. " must close direct-register deps")
    return collectQuotedValues(source:sub(depsStart, depsEnd))
end

local equipInspectSource = nil
pcall(function()
    equipInspectSource = read("!KRT/Services/EquipInspect.lua")
end)
assert(equipInspectSource, "Services/EquipInspect.lua must exist for UI entrypoint registry coverage")

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

local expectedControllers = {
    {
        name = "Controllers/Master",
        path = "!KRT/Controllers/Master.lua",
        owner = "module",
        separator = ":",
        registryFromFeature = true,
        events = "-- events: listens forwarded loot/trade events and Master bus refresh events",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Item",
            "Modules/Colors",
            "Modules/Comms",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
            "Modules/UI/MultiSelect",
            "Services/Chat",
            "Services/Loot/Service",
            "Services/Rolls/Service",
            "Services/Raid/State",
            "Services/Raid/Capabilities",
            "Services/Raid/Roster",
            "Services/Raid/LootRecords",
            "Services/Raid/LootMethod",
        },
        forbiddenDeps = {
            "Services/Reserves",
            "Services/Logger/Store",
            "Services/Logger/View",
            "Services/Logger/Export",
            "Services/Logger/Helpers",
            "Services/Logger/Actions",
            "Services/Raid/Counts",
            "Services/Raid/Session",
            "Services/Loot/Rules",
            "Services/Loot/DistributionSession",
        },
    },
    {
        name = "Controllers/Logger",
        path = "!KRT/Controllers/Logger.lua",
        owner = "module",
        separator = ":",
        noPublicApi = true,
        registryFromFeature = true,
        events = "-- events: listens Logger/Raid/Loot bus refresh events",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Colors",
            "Modules/Base64",
            "Modules/Sort",
            "Modules/Dataset/IgnoredMobs",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
            "Modules/UI/MultiSelect",
            "Services/Logger/Store",
            "Services/Logger/View",
            "Services/Logger/Export",
            "Services/Logger/Helpers",
            "Services/Logger/Actions",
        },
        forbiddenPrefixes = { "Services/Raid/", "Services/Loot/" },
        forbiddenDeps = { "Services/Chat" },
    },
    {
        name = "Controllers/Warnings",
        path = "!KRT/Controllers/Warnings.lua",
        owner = "module",
        separator = ":",
        registryFromFeature = true,
        events = "-- events: owns warning UI scripts; sends announcements through Services/Chat",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
            "Services/Warnings/Store",
            "Services/Chat",
        },
        forbiddenPrefixes = { "Services/Raid/" },
        forbiddenDeps = { "Modules/Events", "Modules/Bus" },
    },
    {
        name = "Controllers/Spammer",
        path = "!KRT/Controllers/Spammer.lua",
        owner = "module",
        separator = ":",
        registryFromFeature = true,
        events = "-- events: owns spammer UI scripts; delegates ticker state to Services/Chat",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Spammer/Draft",
            "Services/Chat",
        },
        forbiddenPrefixes = { "Services/Raid/" },
        forbiddenDeps = { "Modules/Events", "Modules/Bus" },
    },
}

local expectedWidgets = {
    {
        name = "Widgets/RaidGrid",
        path = "!KRT/Widgets/RaidGrid.lua",
        gate = 'UIWidgets.IsEnabled("RaidGrid")',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Bus",
            "Modules/Colors",
            "Services/SpecInspect",
            "Modules/UI/Facade",
            "Modules/UI/Visuals",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/", "Services/Raid/", "Services/Loot/", "Services/Master/" },
    },
    {
        name = "Widgets/LootHints",
        path = "!KRT/Widgets/LootHints.lua",
        gate = 'UIWidgets.IsEnabled("LootHints")',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/", "Services/Rolls/", "Services/Loot/" },
    },
    {
        name = "Widgets/LootCounter",
        path = "!KRT/Widgets/LootCounter.lua",
        gate = 'UIWidgets.IsEnabled("LootCounter")',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Colors",
            "Modules/Events",
            "Modules/Bus",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Chat",
            "Services/Raid/State",
            "Services/Raid/Capabilities",
            "Services/Raid/Counts",
            "Services/Raid/Roster",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/", "Services/Rolls/", "Services/Loot/" },
    },
    {
        name = "Widgets/ReservesUI",
        path = "!KRT/Widgets/ReservesUI.lua",
        gate = 'UIWidgets.IsEnabled("Reserves")',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Colors",
            "Modules/Events",
            "Modules/Bus",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Chat",
            "Services/Reserves",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/" },
        forbiddenDeps = {
            "Services/Reserves/Import",
            "Services/Reserves/Aliases",
            "Services/Reserves/Display",
            "Services/Reserves/Sync",
            "Services/Reserves/Chat",
        },
    },
    {
        name = "Widgets/Config",
        path = "!KRT/Widgets/Config.lua",
        gate = 'UIWidgets.IsEnabled("Config")',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/OptionsLayout",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/", "Services/" },
        forbiddenDeps = { "EntryPoints/Minimap" },
    },
}

local expectedEntryPoints = {
    {
        name = "EntryPoints/Minimap",
        path = "!KRT/EntryPoints/Minimap.lua",
        owner = "module",
        separator = ":",
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Colors",
            "Modules/UI/Frames",
            "Modules/UI/Facade",
        },
        events = "-- events: owns minimap frame scripts; drag uses allowed OnUpdate exception",
    },
    {
        name = "EntryPoints/SlashEvents",
        path = "!KRT/EntryPoints/SlashEvents.lua",
        metadataAfterNeedle = 'SlashCmdList["KRT"] = function(msg)',
        registryFromFeature = true,
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Colors",
            "Modules/Strings",
            "Modules/Comms",
            "Modules/Item",
            "Modules/UI/Frames",
            "Modules/UI/Facade",
        },
        forbiddenDeps = { "EntryPoints/Minimap", "Database/DBSyncer", "Database/DBRaidValidator" },
        events = "-- events: owns /krt slash command routing; dispatches Controller, Widget, and sync commands",
    },
}

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
    { name = "Modules/LootSourceCandidates", deps = { "Init", "Modules/Strings" } },
    { name = "Modules/LootSourcesData", deps = { "Init", "Modules/LootSourceCandidates" } },
    { name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/LootSourceCandidates", "Modules/LootSourcesData" } },
    { name = "Modules/IgnoredItems", deps = { "Init" } },
    { name = "Modules/Dataset/IgnoredMobs", deps = { "Init" } },
    { name = "Modules/Comms", deps = { "Init" } },
    { name = "Modules/Time", deps = { "Init" } },
    { name = "Modules/Base64", deps = { "Init" } },
    { name = "Modules/Sort", deps = { "Init" } },
    { name = "Modules/Features", deps = { "Init" } },
}

local directRegistryModules = {
    { name = "Modules/UI/Facade", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Effects", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry", "Modules/Colors", "Modules/UI/Effects" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames", "Modules/UI/Visuals" } },
    { name = "Modules/UI/MultiSelect", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/OptionsLayout", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Frames" } },
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
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DB",
            "Database/DBRaidStore",
            "Modules/Strings",
            "Modules/Sort",
            "Modules/LootSourceCandidates",
        },
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
    deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Timer", "Modules/Strings", "Modules/Comms" },
}

local expectedEquipInspectService = {
    name = "Services/EquipInspect",
    deps = {
        "Init",
        "Modules/ModuleRegistry",
        "Modules/Events",
        "Modules/Bus",
        "Modules/Timer",
        "Modules/Strings",
        "Services/Raid/Roster",
        "Services/Raid/Attendance",
        "Services/SpecInspect",
    },
}

local expectedSpammerServices = {
    {
        name = "Services/Spammer/Draft",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
    },
    {
        name = "Services/Warnings/Store",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" },
    },
}

local expectedLootServices = {
    { name = "Services/Loot/Context", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/LootSourceCandidates" } },
    { name = "Services/Loot/State", deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Services/Loot/Context" } },
    {
        name = "Services/Loot/Snapshots",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Services/Loot/State", "Services/Loot/Context" },
    },
    {
        name = "Services/Loot/PendingAwards",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item" },
    },
    {
        name = "Services/Loot/PassiveGroupLoot",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Strings" },
    },
    {
        name = "Services/Loot/Tracking",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Item",
            "Services/Loot/Context",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
        },
    },
    {
        name = "Services/Loot/Rules",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/IgnoredItems" },
    },
    {
        name = "Services/Loot/DistributionSession",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Comms", "Modules/Item" },
    },
    {
        name = "Services/Loot/Service",
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
            "Modules/IgnoredItems",
            "Services/Loot/Context",
            "Services/Loot/PendingAwards",
            "Services/Loot/PassiveGroupLoot",
            "Services/Loot/Tracking",
        },
    },
}

local expectedRaidServices = {
    {
        name = "Services/Raid/State",
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
    },
    { name = "Services/Raid/Capabilities", deps = { "Init", "Modules/ModuleRegistry" } },
    {
        name = "Services/Raid/Counts",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Strings" },
    },
    {
        name = "Services/Raid/Roster",
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
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Time" },
    },
    {
        name = "Services/Raid/LootRecords",
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
    { name = "Services/Raid/Session", deps = { "Init", "Modules/ModuleRegistry" } },
    {
        name = "Services/Raid/LootMethod",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Events",
            "Modules/Bus",
            "Database/DBOptions",
            "Services/Raid/Capabilities",
        },
    },
}

local expectedRollServices = {
    {
        name = "Services/Rolls/Countdown",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Timer", "Services/Chat" },
    },
    { name = "Services/Rolls/Sessions", deps = { "Init", "Modules/ModuleRegistry", "Modules/Item", "Modules/Strings" } },
    { name = "Services/Rolls/History", deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus" } },
    {
        name = "Services/Rolls/Responses",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Services/Chat" },
    },
    { name = "Services/Rolls/Strategies", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Services/Rolls/Resolution", deps = { "Init", "Modules/ModuleRegistry" } },
    {
        name = "Services/Rolls/Display",
        deps = { "Init", "Modules/ModuleRegistry", "Services/Rolls/Responses", "Services/Rolls/Resolution" },
    },
    {
        name = "Services/Rolls/Service",
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
    },
}

local expectedDebugServices = {
    { name = "Services/Debug", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Time" } },
}

local expectedReservesServices = {
    { name = "Services/Reserves/Import", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" } },
    { name = "Services/Reserves/Aliases", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" } },
    {
        name = "Services/Reserves/Display",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings", "Services/Reserves/Aliases" },
    },
    { name = "Services/Reserves/Sync", deps = { "Init", "Modules/ModuleRegistry", "Modules/Comms", "Modules/Strings" } },
    {
        name = "Services/Reserves",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Timer",
            "Modules/Events",
            "Modules/Bus",
            "Modules/Strings",
            "Modules/Item",
            "Modules/LootSources",
            "Services/Reserves/Import",
            "Services/Reserves/Aliases",
            "Services/Reserves/Display",
        },
    },
    {
        name = "Services/Reserves/Chat",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Modules/Events", "Modules/Bus" },
    },
}

local expectedLoggerServices = {
    { name = "Services/Logger/Store", deps = { "Init", "Modules/ModuleRegistry", "Database/DBRaidQueries", "Modules/Strings" } },
    {
        name = "Services/Logger/Helpers",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Services/Logger/Store" },
    },
    { name = "Services/Logger/View", deps = { "Init", "Modules/ModuleRegistry", "Modules/Sort", "Services/Logger/Store", "Modules/LootSourceCandidates" } },
    { name = "Services/Logger/Export", deps = { "Init", "Modules/ModuleRegistry", "Services/Logger/Store", "Services/Logger/Helpers" } },
    {
        name = "Services/Logger/Actions",
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/Base64",
            "Services/Logger/Store",
            "Services/Logger/Helpers",
        },
    },
}

local moduleTocPaths = {
    ["Init"] = "Init.lua",
    ["Database/DBOptions"] = "Database\\DBOptions.lua",
    ["Database/DB"] = "Database\\DB.lua",
    ["Database/DBSchema"] = "Database\\DBSchema.lua",
    ["Database/DBManager"] = "Database\\DBManager.lua",
    ["Database/DBRaidMigrations"] = "Database\\DBRaidMigrations.lua",
    ["Database/DBRaidStore"] = "Database\\DBRaidStore.lua",
    ["Database/DBRaidQueries"] = "Database\\DBRaidQueries.lua",
    ["Database/DBRaidValidator"] = "Database\\DBRaidValidator.lua",
    ["Database/DBSyncer"] = "Database\\DBSyncer.lua",
    ["Modules/C"] = "Modules\\C.lua",
    ["Modules/Timer"] = "Modules\\Timer.lua",
    ["Modules/Events"] = "Modules\\Events.lua",
    ["Modules/Colors"] = "Modules\\Colors.lua",
    ["Modules/Strings"] = "Modules\\Strings.lua",
    ["Modules/Item"] = "Modules\\Item.lua",
    ["Modules/LootSourcesData"] = "Modules\\LootSourcesData.lua",
    ["Modules/LootSourceCandidates"] = "Modules\\LootSourceCandidates.lua",
    ["Modules/LootSources"] = "Modules\\LootSources.lua",
    ["Modules/IgnoredItems"] = "Modules\\IgnoredItems.lua",
    ["Modules/Dataset/IgnoredMobs"] = "Modules\\Dataset\\IgnoredMobs.lua",
    ["Modules/Comms"] = "Modules\\Comms.lua",
    ["Modules/Time"] = "Modules\\Time.lua",
    ["Modules/Base64"] = "Modules\\Base64.lua",
    ["Modules/Sort"] = "Modules\\Sort.lua",
    ["Modules/Features"] = "Modules\\Features.lua",
    ["Modules/ModuleRegistry"] = "Modules\\ModuleRegistry.lua",
    ["Modules/UI/Facade"] = "Modules\\UI\\Facade.lua",
    ["Modules/UI/Effects"] = "Modules\\UI\\Effects.lua",
    ["Modules/UI/Visuals"] = "Modules\\UI\\Visuals.lua",
    ["Modules/UI/Frames"] = "Modules\\UI\\Frames.lua",
    ["Modules/UI/ListController"] = "Modules\\UI\\ListController.lua",
    ["Modules/UI/MultiSelect"] = "Modules\\UI\\MultiSelect.lua",
    ["Modules/UI/OptionsLayout"] = "Modules\\UI\\OptionsLayout.lua",
    ["Modules/Bus"] = "Modules\\Bus.lua",
    ["Services/Chat"] = "Services\\Chat.lua",
    ["Services/Loot/Context"] = "Services\\Loot\\Context.lua",
    ["Services/Loot/State"] = "Services\\Loot\\State.lua",
    ["Services/Loot/Snapshots"] = "Services\\Loot\\Snapshots.lua",
    ["Services/Loot/PendingAwards"] = "Services\\Loot\\PendingAwards.lua",
    ["Services/Loot/PassiveGroupLoot"] = "Services\\Loot\\PassiveGroupLoot.lua",
    ["Services/Loot/Tracking"] = "Services\\Loot\\Tracking.lua",
    ["Services/Loot/Rules"] = "Services\\Loot\\Rules.lua",
    ["Services/Loot/DistributionSession"] = "Services\\Loot\\DistributionSession.lua",
    ["Services/Loot/Service"] = "Services\\Loot\\Service.lua",
    ["Services/EquipInspect"] = "Services\\EquipInspect.lua",
    ["Services/Raid/State"] = "Services\\Raid\\State.lua",
    ["Services/Raid/Capabilities"] = "Services\\Raid\\Capabilities.lua",
    ["Services/Raid/Counts"] = "Services\\Raid\\Counts.lua",
    ["Services/Raid/Roster"] = "Services\\Raid\\Roster.lua",
    ["Services/Raid/Attendance"] = "Services\\Raid\\Attendance.lua",
    ["Services/Raid/LootRecords"] = "Services\\Raid\\LootRecords.lua",
    ["Services/Raid/Session"] = "Services\\Raid\\Session.lua",
    ["Services/Raid/LootMethod"] = "Services\\Raid\\LootMethod.lua",
    ["Services/Rolls/Countdown"] = "Services\\Rolls\\Countdown.lua",
    ["Services/Rolls/Sessions"] = "Services\\Rolls\\Sessions.lua",
    ["Services/Rolls/History"] = "Services\\Rolls\\History.lua",
    ["Services/Rolls/Responses"] = "Services\\Rolls\\Responses.lua",
    ["Services/Rolls/Resolution"] = "Services\\Rolls\\Resolution.lua",
    ["Services/Rolls/Display"] = "Services\\Rolls\\Display.lua",
    ["Services/Rolls/Service"] = "Services\\Rolls\\Service.lua",
    ["Services/Debug"] = "Services\\Debug.lua",
    ["Services/Reserves/Import"] = "Services\\Reserves\\Import.lua",
    ["Services/Reserves/Aliases"] = "Services\\Reserves\\Aliases.lua",
    ["Services/Reserves/Display"] = "Services\\Reserves\\Display.lua",
    ["Services/Reserves/Sync"] = "Services\\Reserves\\Sync.lua",
    ["Services/Reserves"] = "Services\\Reserves.lua",
    ["Services/Reserves/Chat"] = "Services\\Reserves\\Chat.lua",
    ["Services/Spammer/Draft"] = "Services\\Spammer\\Draft.lua",
    ["Services/Warnings/Store"] = "Services\\Warnings\\Store.lua",
    ["Services/SpecInspect"] = "Services\\SpecInspect.lua",
    ["Services/Logger/Store"] = "Services\\Logger\\Store.lua",
    ["Services/Logger/View"] = "Services\\Logger\\View.lua",
    ["Services/Logger/Export"] = "Services\\Logger\\Export.lua",
    ["Services/Logger/Helpers"] = "Services\\Logger\\Helpers.lua",
    ["Services/Logger/Actions"] = "Services\\Logger\\Actions.lua",
    ["Controllers/Master"] = "Controllers\\Master.lua",
    ["Controllers/Logger"] = "Controllers\\Logger.lua",
    ["Controllers/Warnings"] = "Controllers\\Warnings.lua",
    ["Controllers/Spammer"] = "Controllers\\Spammer.lua",
    ["Widgets/RaidGrid"] = "Widgets\\RaidGrid.lua",
    ["Widgets/LootHints"] = "Widgets\\LootHints.lua",
    ["Widgets/LootCounter"] = "Widgets\\LootCounter.lua",
    ["Widgets/ReservesUI"] = "Widgets\\ReservesUI.lua",
    ["Widgets/Config"] = "Widgets\\Config.lua",
    ["EntryPoints/Minimap"] = "EntryPoints\\Minimap.lua",
    ["EntryPoints/SlashEvents"] = "EntryPoints\\SlashEvents.lua",
}

local function assertNoForbiddenDeps(expected, deps)
    for i = 1, #deps do
        local dep = deps[i]
        assert(dep:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
        if expected.name:match("^Controllers/") then
            assert(dep:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
        elseif expected.name:match("^EntryPoints/") then
            assert(dep:match("^Controllers/") == nil, expected.name .. " must not depend on Controllers")
            assert(dep:match("^Widgets/") == nil, expected.name .. " must not depend on Widgets")
            assert(dep:match("^Services/") == nil, expected.name .. " must not depend on Services")
        end

        if expected.forbiddenPrefixes then
            for j = 1, #expected.forbiddenPrefixes do
                assert(dep:sub(1, #expected.forbiddenPrefixes[j]) ~= expected.forbiddenPrefixes[j], expected.name .. " must not hard-depend on " .. expected.forbiddenPrefixes[j])
            end
        end
        if expected.forbiddenDeps then
            for j = 1, #expected.forbiddenDeps do
                assert(dep ~= expected.forbiddenDeps[j], expected.name .. " must not hard-depend on " .. dep)
            end
        end
        if expected.name:match("^Widgets/") then
            assert(dep ~= "Modules/UI/ListController", expected.name .. " must not depend on ListController")
            assert(dep ~= "Modules/UI/MultiSelect", expected.name .. " must not depend on MultiSelect")
        end
    end
end

local function assertDependencyTocOrder(expected, toc)
    local targetPath = assert(moduleTocPaths[expected.name], "missing target TOC path: " .. expected.name)
    for i = 1, #expected.deps do
        local depPath = moduleTocPaths[expected.deps[i]]
        if depPath then
            assertBefore(toc, depPath, targetPath, expected.deps[i] .. " must load before " .. expected.name)
        end
    end
end

local function assertDirectRegistryContract(expected, source)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    assert(metadataStart, expected.name .. " must direct-register module metadata")
    if expected.registryFromFeature then
        assertContains(source, "local registry = feature.ModuleRegistry", expected.name .. " must localize ModuleRegistry from feature shared")
        assertNotContains(source, "local registry = addon.ModuleRegistry", expected.name .. " must not read ModuleRegistry directly from addon root")
    else
        assertContains(source, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
    end
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark module loaded")
    assertNotContains(source, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")
    if expected.events then
        assertContains(source, expected.events, expected.name .. " must document concrete event ownership in the Lua contract")
        assertNotContains(source, "-- events: document inbound/outbound events in module body", expected.name .. " must not keep the generic event placeholder")
    end

    local deps = getPostRegistryDeps(source, expected.name)
    assertDeps(deps, expected.deps, expected.name)
    assertNoForbiddenDeps(expected, deps)
end

local function assertControllerMetadata(expected)
    local source = read(expected.path)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local publicApiStart = findLastExportedFunction(source, expected.owner, expected.separator)
    assertDirectRegistryContract(expected, source)
    if expected.noPublicApi then
        assert(not publicApiStart, expected.name .. " must not expose controller public API")
    else
        assert(publicApiStart, expected.name .. " must expose public API before registry metadata")
        assert(publicApiStart < metadataStart, expected.name .. " metadata must appear after public API tail")
    end
end

local function assertWidgetMetadata(expected)
    local source = read(expected.path)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    local gateStart = source:find(expected.gate, 1, true)
    assertDirectRegistryContract(expected, source)
    assert(gateStart, expected.name .. " must retain its feature gate")
    assert(metadataStart < gateStart, expected.name .. " metadata must appear before the feature gate return path")
end

local function assertEntryPointMetadata(expected)
    local source = read(expected.path)
    local metadataStart = source:find('registry.AddModule("' .. expected.name .. '"', 1, true)
    assertDirectRegistryContract(expected, source)
    if expected.metadataAfterNeedle then
        local anchor = source:find(expected.metadataAfterNeedle, 1, true)
        assert(anchor, expected.name .. " must retain slash registration anchor")
        assert(anchor < metadataStart, expected.name .. " metadata must appear after slash registration")
    else
        local publicApiStart = findLastExportedFunction(source, expected.owner, expected.separator)
        assert(publicApiStart, expected.name .. " must expose public API before registry metadata")
        assert(publicApiStart < metadataStart, expected.name .. " metadata must appear after public API tail")
    end
end

local scaffoldControllerMethods = {
    BindUI = true,
    EnsureUI = true,
    Hide = true,
    MarkDirty = true,
    RequestRefresh = true,
    Show = true,
    Toggle = true,
}

local controllerPaths = {
    Logger = "!KRT/Controllers/Logger.lua",
    Master = "!KRT/Controllers/Master.lua",
    Spammer = "!KRT/Controllers/Spammer.lua",
    Warnings = "!KRT/Controllers/Warnings.lua",
}

local scaffoldedControllerNamespacePaths = {
    Logger = "!KRT/Controllers/Logger.lua",
    Spammer = "!KRT/Controllers/Spammer.lua",
    Warnings = "!KRT/Controllers/Warnings.lua",
}

local localLimitControllerNamespacePaths = {
    Master = "!KRT/Controllers/Master.lua",
}

local widgetPaths = {
    Config = "!KRT/Widgets/Config.lua",
    LootCounter = "!KRT/Widgets/LootCounter.lua",
    RaidGrid = "!KRT/Widgets/RaidGrid.lua",
    LootHints = "!KRT/Widgets/LootHints.lua",
    Reserves = "!KRT/Widgets/ReservesUI.lua",
}

local standardWidgetMethods = {
    Hide = true,
    RequestRefresh = true,
    Toggle = true,
}

local function assertModuleMethod(source, methodName, context)
    local pattern = "function%s+module%:" .. methodName .. "%s*%("
    local assignedPattern = "module%." .. methodName .. "%s*=%s*function%s*%("
    local message = context .. " must expose function module:" .. methodName .. "("
    assert(source:find(pattern) or source:find(assignedPattern), message)
end

local function assertWidgetMethod(source, methodName, context)
    local pattern = methodName .. "%s*=%s*function%s*%("
    local modulePattern = "function%s+module%." .. methodName .. "%s*%("
    local message = context .. " must expose " .. methodName .. " = function"
    assert(source:find(pattern) or source:find(modulePattern), message)
end

local function assertControllerDispatchPair(controllerName, methodName, sourcePath)
    local controllerPath = controllerPaths[controllerName]
    assert(controllerPath, sourcePath .. " dispatches unknown controller: " .. controllerName)

    local controllerSource = read(controllerPath)
    local context = sourcePath .. " -> " .. controllerName .. ":" .. methodName

    if scaffoldControllerMethods[methodName] then
        local message = context .. " must be backed by UI.Scaffold.DefineModule"
        assert(controllerSource:find("Scaffold.DefineModule({", 1, true) or controllerSource:find("UI.Scaffold.DefineModule({", 1, true), message)
    else
        assertModuleMethod(controllerSource, methodName, context)
    end
end

local function assertControllerDispatchContracts()
    local scans = {
        {
            path = "!KRT/EntryPoints/SlashEvents.lua",
            pattern = 'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            pattern = 'callControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
    }
    local total = 0

    for i = 1, #scans do
        local scan = scans[i]
        local source = read(scan.path)
        local count = 0

        for controllerName, methodName in source:gmatch(scan.pattern) do
            assertControllerDispatchPair(controllerName, methodName, scan.path)
            count = count + 1
            total = total + 1
        end

        assert(count > 0, scan.path .. " must contain literal controller dispatch pairs")
    end

    assert(total > 0, "controller dispatch sweep must find literal dispatch pairs")
end

local function assertWidgetDispatchPair(widgetId, methodName, sourcePath)
    local widgetPath = widgetPaths[widgetId]
    assert(widgetPath, sourcePath .. " dispatches unknown widget: " .. widgetId)

    local widgetSource = read(widgetPath)
    local context = sourcePath .. " -> " .. widgetId .. ":" .. methodName

    if standardWidgetMethods[methodName] then
        local message = context .. " must be backed by UI.Scaffold.CreateWidgetApi"
        assert(
            widgetSource:find("Scaffold.CreateWidgetApi(module,", 1, true)
                or widgetSource:find(methodName .. "%s*=%s*function%s*%(")
                or widgetSource:find("function%s+module%." .. methodName .. "%s*%("),
            message
        )
    else
        assertWidgetMethod(widgetSource, methodName, context)
    end
end

local function assertWidgetDispatchContracts()
    local scans = {
        {
            path = "!KRT/EntryPoints/SlashEvents.lua",
            pattern = 'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
            required = true,
        },
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            pattern = 'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
            required = true,
        },
        {
            path = "!KRT/Controllers/Master.lua",
            pattern = 'UI%.Widgets%.Call%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
        {
            path = "!KRT/Widgets/ReservesUI.lua",
            pattern = 'UIWidgets%.Call%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
    }
    local total = 0

    for i = 1, #scans do
        local scan = scans[i]
        local source = read(scan.path)
        local count = 0

        for widgetId, methodName in source:gmatch(scan.pattern) do
            assertWidgetDispatchPair(widgetId, methodName, scan.path)
            count = count + 1
            total = total + 1
        end

        if scan.required then
            assert(count > 0, scan.path .. " must contain literal widget dispatch pairs")
        end
    end

    assert(total > 0, "widget dispatch sweep must find literal dispatch pairs")
end

local function assertMinimapRaidMenuContract()
    local source = read("!KRT/EntryPoints/Minimap.lua")
    local reservesDispatch = 'callWidgetMethod("Reserves", "Toggle")'
    local lootHistoryDispatch = 'callControllerMethod("Logger", "ToggleLootHistory")'
    local raidAttendanceDispatch = 'callControllerMethod("Logger", "ToggleRaidAttendance")'

    assertContains(source, reservesDispatch, "minimap menu must open Loot Reserve through UI facade")
    assertContains(source, lootHistoryDispatch, "minimap menu must open Loot History through Logger controller")
    assertContains(source, raidAttendanceDispatch, "minimap menu must open Raid Attendance through Logger controller")
    assertNotContains(source, "L.StrLootLogger", "minimap menu must no longer expose the combined logger entry")
    assertNotContains(source, "text = MASTER_LOOTER", "minimap menu must use the Loot Master label")
    assertBefore(source, "L.StrLootMaster", "L.StrLootReserve", "minimap menu must list Loot Master before Loot Reserve")
    assertBefore(source, "L.StrLootReserve", "L.StrLootCounter", "minimap menu must list Loot Reserve before Loot Counter")
    assertBefore(source, "L.StrLootCounter", "L.StrLootHistory", "minimap menu must list Loot Counter before Loot History")
    assertBefore(source, "L.StrLootHistory", "L.StrRaidAttendance", "minimap menu must list Loot History before Raid Attendance")
    assertBefore(source, "L.StrRaidAttendance", "RAID_WARNING", "minimap menu must list Raid Attendance before Raid Warning")
    assertBefore(source, "RAID_WARNING", "L.StrLFMSpam", "minimap menu must list Raid Warning before LFM Spam")
    assertBefore(source, "L.StrLFMSpam", "L.StrClearIcons", "minimap menu must list LFM Spam before Clear Icons")
end

local function assertEntryPointOptionContracts()
    local paths = {
        "!KRT/EntryPoints/SlashEvents.lua",
        "!KRT/EntryPoints/Minimap.lua",
    }
    for i = 1, #paths do
        assertNotContains(read(paths[i]), "addon.options", paths[i] .. " must use namespace cfg:Get/cfg:Set instead of addon.options")
    end
end

local function assertReservesWidgetOptionContract()
    assertNotContains(read("!KRT/Widgets/ReservesUI.lua"), "addon.options", "!KRT/Widgets/ReservesUI.lua must use namespace cfg:Get/cfg:Set instead of addon.options")
end

local function assertLootCounterDependencyLocalContract()
    local source = read("!KRT/Widgets/LootCounter.lua")
    assertContains(source, "local Options = feature.Options", "LootCounter must localize Options from feature shared")
    assertContains(source, "row.specIcon", "LootCounter must render spec icons")
    assertContains(source, "GetPlayerSpecSnapshot", "LootCounter must consume SpecInspect snapshots")
    assertContains(source, "SpecInspectUpdated", "LootCounter must refresh on spec updates")
    assertNotContains(source, "addon.Options", "LootCounter must use the local Options dependency")
    assertNotContains(source, "addon.Database.GetCurrentRaid", "LootCounter must use the local Database dependency")
end

local function assertWidgetFeatureUiDependencyContract()
    local widgetSources = {
        {
            path = "!KRT/Widgets/LootCounter.lua",
            needsPrimitives = false,
        },
        {
            path = "!KRT/Widgets/ReservesUI.lua",
            needsPrimitives = true,
        },
        {
            path = "!KRT/Widgets/Config.lua",
            needsPrimitives = false,
        },
    }

    for i = 1, #widgetSources do
        local spec = widgetSources[i]
        local source = read(spec.path)
        assertContains(source, "local UI = feature.UI", spec.path .. " must localize UI root from feature shared")
        assertContains(source, "local UIWidgets = UI.Widgets", spec.path .. " must localize widget facade from UI root")
        assertContains(source, "local Scaffold = UI.Scaffold", spec.path .. " must localize scaffold helpers from UI root")
        assertNotContains(source, "local UIScaffold = addon.UIScaffold", spec.path .. " must not read UIScaffold from addon root")
        assertNotContains(source, "local UIFacade = addon.UI", spec.path .. " must not read UI facade from addon root")
        assertNotContains(source, "feature.UIScaffold", spec.path .. " must not use legacy UIScaffold feature field")
        if spec.needsPrimitives then
            assertContains(source, "local Primitives = UI.Primitives", spec.path .. " must localize primitives from UI root")
            assertNotContains(source, "local UIPrimitives = addon.UIPrimitives", spec.path .. " must not read UIPrimitives from addon root")
            assertNotContains(source, "feature.UIPrimitives", spec.path .. " must not use legacy UIPrimitives feature field")
        end
    end

    local reservesSource = read("!KRT/Widgets/ReservesUI.lua")
    assertContains(reservesSource, "local Services = feature.Services", "ReservesUI must localize Services from feature shared")
    assertNotContains(reservesSource, "addon.Services and addon.Services.Reserves", "ReservesUI must not read Reserves service from addon root")
end

local function assertWidgetNamespaceContracts()
    for widgetName, path in pairs(widgetPaths) do
        local source = read(path)
        assertContains(source, "local Widgets = feature.Widgets", path .. " must localize Widgets from feature shared")
        assertContains(source, "local module = Widgets." .. widgetName, path .. " must bind module through the local Widgets namespace")
        assertNotContains(source, "local module = addon.Widgets." .. widgetName, path .. " must not bind module through addon.Widgets")
    end
end

local function assertWidgetEventHeaderContracts()
    local headers = {
        {
            path = "!KRT/Widgets/Config.lua",
            events = "-- events: emits option-specific events; listens OptionsLoaded",
        },
        {
            path = "!KRT/Widgets/LootCounter.lua",
            events = "-- events: listens RaidRosterDelta, PlayerCountChanged, RaidCreate",
        },
        {
            path = "!KRT/Widgets/ReservesUI.lua",
            events = "-- events: listens ReservesDataChanged and GET_ITEM_INFO_RECEIVED",
        },
    }

    for i = 1, #headers do
        local spec = headers[i]
        local source = read(spec.path)
        assertContains(source, spec.events, spec.path .. " must document concrete event ownership in the Lua contract")
        assertNotContains(source, "-- events: document inbound/outbound events in module body", spec.path .. " must not keep the generic event placeholder")
    end
end

local function assertEntryPointFeatureUiDependencyContract()
    local entryPointSources = {
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            localName = "UI",
        },
        {
            path = "!KRT/EntryPoints/SlashEvents.lua",
            localName = "UI",
        },
    }

    for i = 1, #entryPointSources do
        local spec = entryPointSources[i]
        local source = read(spec.path)
        assertContains(source, "local " .. spec.localName .. " = feature.UI", spec.path .. " must localize UI root from feature shared")
        assertContains(source, "local UIWidgets = UI.Widgets", spec.path .. " must localize widget facade from UI root")
        assertNotContains(source, "local " .. spec.localName .. " = addon.UI", spec.path .. " must not read UI facade from addon root")
    end

    local slashSource = read("!KRT/EntryPoints/SlashEvents.lua")
    assertContains(slashSource, "local Timer = feature.Timer", "SlashEvents must localize Timer from feature shared")
    assertNotContains(slashSource, "addon.Timer", "SlashEvents must use the local Timer dependency")
    assertContains(slashSource, "local Features = feature.Features", "SlashEvents must localize Features from feature shared")
    assertNotContains(slashSource, "local features = addon.Features", "SlashEvents must use the local Features dependency")
    assertContains(slashSource, "local coreState = feature.coreState", "SlashEvents must localize core state from feature shared")
    assertNotContains(slashSource, "local coreState = feature.coreState or addon.State", "SlashEvents must not fall back to addon.State for core state")
    assertNotContains(slashSource, "addon.State and addon.State.perfThresholdMs", "SlashEvents must use local coreState for perf threshold")
    assertNotContains(slashSource, "addon.State and addon.State.perfEnabled", "SlashEvents must use local coreState for perf enabled")
    assertContains(slashSource, "cmdSpecInspect", "SlashEvents must wire cmdSpecInspect in command assertions")
    assertContains(slashSource, "handleSpecInspectCommand", "SlashEvents must wire handleSpecInspectCommand in command assertions")
    assertContains(slashSource, "Services.SpecInspect", "SlashEvents should route to Services.SpecInspect")
end

local function assertEntryPointOwnerTableContracts()
    local initSource = read("!KRT/Init.lua")
    assertContains(initSource, "Minimap = addon.Minimap", "feature shared contract must expose the Minimap entrypoint owner table")

    local minimapSource = read("!KRT/EntryPoints/Minimap.lua")
    assertContains(minimapSource, "local module = feature.Minimap", "Minimap must bind its owner table from feature shared")
    assertContains(minimapSource, "feature.Minimap = feature.Minimap or {}", "Minimap must initialize its owner table from feature shared")
    assertNotContains(minimapSource, "feature.Minimap = feature.Minimap or addon.Minimap or {}", "Minimap must not double-bind its owner table through addon root")
    assertNotContains(minimapSource, "local module = addon.Minimap", "Minimap must not bind its owner table directly from addon root")
end

local function assertSyncerDispatchContracts()
    local slashSource = read("!KRT/EntryPoints/SlashEvents.lua")
    local syncerSource = read("!KRT/Database/DBSyncer.lua")
    local scans = {
        {
            pattern = 'callSyncerMethod%("([%w_]+)"',
            label = "callSyncerMethod",
        },
        {
            pattern = 'callSyncerMethodWithTarget%("([%w_]+)"',
            label = "callSyncerMethodWithTarget",
        },
    }
    local total = 0

    for i = 1, #scans do
        local scan = scans[i]
        local count = 0

        for methodName in slashSource:gmatch(scan.pattern) do
            local context = "SlashEvents " .. scan.label .. " -> Syncer:" .. methodName
            assertModuleMethod(syncerSource, methodName, context)
            count = count + 1
            total = total + 1
        end

        assert(count > 0, "SlashEvents must contain literal " .. scan.label .. " dispatch pairs")
    end

    assert(total > 0, "syncer dispatch sweep must find literal dispatch pairs")
end

local function assertMasterWowForwardedContracts()
    local masterSource = read("!KRT/Controllers/Master.lua")
    local total = 0

    for methodName in masterSource:gmatch('registerWowForwarded%("([%w_]+)"') do
        local context = "Master registerWowForwarded -> Master:" .. methodName
        assertModuleMethod(masterSource, methodName, context)
        total = total + 1
    end

    assert(total > 0, "Master wow-forwarded dispatch sweep must find literal dispatch pairs")
end

local function assertScaffoldedControllerNamespaceContracts()
    for controllerName, path in pairs(scaffoldedControllerNamespacePaths) do
        local source = read(path)
        assertContains(source, "local Controllers = feature.Controllers", path .. " must localize Controllers from feature shared")
        assertContains(source, "local module = Controllers." .. controllerName, path .. " must bind module through the local Controllers namespace")
        assertNotContains(source, "local module = addon.Controllers." .. controllerName, path .. " must not bind module through addon.Controllers")
    end

    local loggerSource = read("!KRT/Controllers/Logger.lua")
    assertContains(loggerSource, "local coreState = feature.coreState", "Logger must localize core state from feature shared")
    assertNotContains(loggerSource, "local coreState = feature.coreState or addon.State", "Logger must not fall back to addon.State for core state")
    assertNotContains(loggerSource, "local state = addon.State", "Logger must use local coreState for selected raid state")
    assertNotContains(loggerSource, "state.selectedRaid", "Logger must use coreState for selected raid state")

    local warningsSource = read("!KRT/Controllers/Warnings.lua")
    assertContains(warningsSource, "local coreState = feature.coreState", "Warnings must localize core state from feature shared")
    assertNotContains(warningsSource, "local coreState = feature.coreState or addon.State", "Warnings must not fall back to addon.State for core state")
    assertNotContains(warningsSource, "addon.State and addon.State.warningsSavedVariablesFresh", "Warnings must use local coreState for fresh SavedVariables flag")
    assertNotContains(warningsSource, "addon.State.warningsSavedVariablesFresh", "Warnings must use local coreState for fresh SavedVariables flag writes")
end

local function assertLocalLimitControllerNamespaceContracts()
    for controllerName, path in pairs(localLimitControllerNamespacePaths) do
        local source = read(path)
        assertContains(
            source,
            "feature.Controllers." .. controllerName .. " = feature.Controllers." .. controllerName .. " or {}",
            path .. " must bind through feature.Controllers without adding a top-level Controllers local"
        )
        assertContains(source, "local module = feature.Controllers." .. controllerName, path .. " must localize module from feature.Controllers")
        assertNotContains(source, "local module = addon.Controllers." .. controllerName, path .. " must not bind module through addon.Controllers")
    end
end

local toc = read("!KRT/!KRT.toc")

for i = 1, #expectedControllers do
    assertControllerMetadata(expectedControllers[i])
    assertDependencyTocOrder(expectedControllers[i], toc)
end
for i = 1, #expectedWidgets do
    assertWidgetMetadata(expectedWidgets[i])
    assertDependencyTocOrder(expectedWidgets[i], toc)
end
for i = 1, #expectedEntryPoints do
    assertEntryPointMetadata(expectedEntryPoints[i])
    assertDependencyTocOrder(expectedEntryPoints[i], toc)
end
assertControllerDispatchContracts()
assertWidgetDispatchContracts()
assertMinimapRaidMenuContract()
assertEntryPointOptionContracts()
assertReservesWidgetOptionContract()
assertLootCounterDependencyLocalContract()
assertWidgetFeatureUiDependencyContract()
assertWidgetNamespaceContracts()
assertWidgetEventHeaderContracts()
assertEntryPointFeatureUiDependencyContract()
assertEntryPointOwnerTableContracts()
assertSyncerDispatchContracts()
assertMasterWowForwardedContracts()
assertScaffoldedControllerNamespaceContracts()
assertLocalLimitControllerNamespaceContracts()

local pending = {}
for i = 1, #preRegistryCoreModules do
    pending[#pending + 1] = { name = preRegistryCoreModules[i].name, deps = preRegistryCoreModules[i].deps, loaded = true }
end
for i = 1, #preRegistryUtilityModules do
    pending[#pending + 1] = { name = preRegistryUtilityModules[i].name, deps = preRegistryUtilityModules[i].deps, loaded = true }
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

local function registerList(list)
    for i = 1, #list do
        registry.AddModule(list[i].name, { deps = list[i].deps })
        registry.SetLoaded(list[i].name)
    end
end

registerList(directRegistryModules)
registerList(postRegistryCoreModules)
registerList(expectedLootServices)
registerList(expectedRaidServices)
registry.AddModule(expectedService.name, { deps = expectedService.deps })
registry.SetLoaded(expectedService.name)
registry.AddModule("Services/SpecInspect", { deps = { "Init", "Modules/ModuleRegistry", "Modules/Events", "Modules/Bus", "Modules/Strings", "Services/Raid/Roster" } })
registry.SetLoaded("Services/SpecInspect")
registry.AddModule(expectedEquipInspectService.name, { deps = expectedEquipInspectService.deps })
registry.SetLoaded(expectedEquipInspectService.name)
registerList(expectedEntryPoints)
registerList(expectedRollServices)
registerList(expectedDebugServices)
registerList(expectedSpammerServices)
registry.AddModule(expectedControllers[1].name, { deps = expectedControllers[1].deps })
registry.SetLoaded(expectedControllers[1].name)
registry.AddModule(expectedWidgets[1].name, { deps = expectedWidgets[1].deps })
registry.SetLoaded(expectedWidgets[1].name)
registerList(expectedReservesServices)
registry.AddModule(expectedWidgets[2].name, { deps = expectedWidgets[2].deps })
registry.SetLoaded(expectedWidgets[2].name)
registerList(expectedLoggerServices)
registry.AddModule(expectedControllers[2].name, { deps = expectedControllers[2].deps })
registry.SetLoaded(expectedControllers[2].name)
registry.AddModule(expectedWidgets[3].name, { deps = expectedWidgets[3].deps })
registry.SetLoaded(expectedWidgets[3].name)
for i = 3, #expectedControllers do
    registry.AddModule(expectedControllers[i].name, { deps = expectedControllers[i].deps })
    registry.SetLoaded(expectedControllers[i].name)
end

local ok, issues = registry.GetLoadOrderStatus()
if not ok then
    local issue = issues and issues[1] or {}
    error(
        "UI entrypoint registry load order must validate; first issue=" .. tostring(issue.module) .. " -> " .. tostring(issue.dependency) .. " (" .. tostring(issue.reason) .. ")"
    )
end
assert(issues == nil, "valid UI entrypoint registry sequence must not report dependency issues")

local function findSpec(name)
    local lists = {
        preRegistryCoreModules,
        preRegistryUtilityModules,
        directRegistryModules,
        postRegistryCoreModules,
        expectedLootServices,
        expectedRaidServices,
        { expectedService },
        expectedEntryPoints,
        expectedRollServices,
        { expectedEquipInspectService },
        expectedSpammerServices,
        expectedDebugServices,
        expectedControllers,
        expectedWidgets,
        expectedReservesServices,
        expectedLoggerServices,
    }
    for i = 1, #lists do
        for j = 1, #lists[i] do
            if lists[i][j].name == name then
                return lists[i][j]
            end
        end
    end
    return nil
end

local function assertOutOfOrder(moduleName, dependencyName)
    local moduleSpec = assert(findSpec(moduleName), "missing expected spec: " .. moduleName)
    local dependencySpec = assert(findSpec(dependencyName), "missing expected spec: " .. dependencyName)
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

assertOutOfOrder("Controllers/Master", "Services/Rolls/Service")
assertOutOfOrder("Controllers/Logger", "Services/Logger/Actions")
assertOutOfOrder("Controllers/Warnings", "Services/Chat")
assertOutOfOrder("Controllers/Spammer", "Services/Chat")
assertOutOfOrder("Widgets/LootCounter", "Services/Raid/Counts")
assertOutOfOrder("Widgets/ReservesUI", "Services/Reserves")
assertOutOfOrder("Widgets/Config", "Database/DBOptions")
assertOutOfOrder("EntryPoints/SlashEvents", "Modules/Comms")

print("module registry UI entrypoints source contract passed")
