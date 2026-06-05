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
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Modules/UI/ListController",
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
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/Strings",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Chat",
        },
        forbiddenPrefixes = { "Services/Raid/" },
        forbiddenDeps = { "Modules/Events", "Modules/Bus" },
    },
}

local expectedWidgets = {
    {
        name = "Widgets/LootCounter",
        path = "!KRT/Widgets/LootCounter.lua",
        gate = 'UIFacade:IsEnabled("LootCounter")',
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
        gate = 'UIFacade:IsEnabled("Reserves")',
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Modules/C",
            "Modules/Events",
            "Modules/Bus",
            "Modules/UI/Facade",
            "Modules/UI/Frames",
            "Modules/UI/Visuals",
            "Services/Reserves",
        },
        forbiddenPrefixes = { "Controllers/", "EntryPoints/" },
        forbiddenDeps = {
            "Services/Reserves/Import",
            "Services/Reserves/Display",
            "Services/Reserves/Sync",
            "Services/Reserves/Chat",
        },
    },
    {
        name = "Widgets/Config",
        path = "!KRT/Widgets/Config.lua",
        gate = 'UIFacade:IsEnabled("Config")',
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
        deps = {
            "Init",
            "Modules/ModuleRegistry",
            "Database/DBOptions",
            "Modules/C",
            "Modules/Colors",
            "Modules/UI/Frames",
            "Modules/UI/Facade",
        },
    },
    {
        name = "EntryPoints/SlashEvents",
        path = "!KRT/EntryPoints/SlashEvents.lua",
        metadataAfterNeedle = 'SlashCmdList["KRT"] = function(msg)',
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
    { name = "Modules/LootSourcesData", deps = { "Init" } },
    { name = "Modules/LootSources", deps = { "Init", "Modules/Strings", "Modules/LootSourcesData" } },
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
    { name = "Modules/UI/Visuals", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/Frames", deps = { "Init", "Modules/ModuleRegistry" } },
    { name = "Modules/UI/ListController", deps = { "Init", "Modules/ModuleRegistry", "Modules/UI/Visuals" } },
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
    deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Timer", "Modules/Strings", "Modules/Comms" },
}

local expectedLootServices = {
    { name = "Services/Loot/Context", deps = { "Init", "Modules/ModuleRegistry" } },
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
        deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Item", "Modules/Strings", "Services/Raid/Counts" },
    },
    { name = "Services/Raid/Session", deps = { "Init", "Modules/ModuleRegistry" } },
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
            "Services/Rolls/Resolution",
            "Services/Rolls/Display",
        },
    },
}

local expectedDebugServices = {
    { name = "Services/Debug", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Time" } },
}

local expectedReservesServices = {
    { name = "Services/Reserves/Import", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" } },
    { name = "Services/Reserves/Display", deps = { "Init", "Modules/ModuleRegistry", "Modules/C", "Modules/Strings" } },
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
            "Services/Reserves/Import",
            "Services/Reserves/Display",
        },
    },
    {
        name = "Services/Reserves/Chat",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Modules/Comms", "Modules/Events", "Modules/Bus" },
    },
}

local expectedLoggerServices = {
    { name = "Services/Logger/Store", deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings" } },
    { name = "Services/Logger/View", deps = { "Init", "Modules/ModuleRegistry", "Modules/Sort", "Services/Logger/Store" } },
    { name = "Services/Logger/Export", deps = { "Init", "Modules/ModuleRegistry", "Services/Logger/Store" } },
    {
        name = "Services/Logger/Helpers",
        deps = { "Init", "Modules/ModuleRegistry", "Modules/Strings", "Services/Logger/Store", "Services/Logger/View" },
    },
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
    ["Services/Raid/State"] = "Services\\Raid\\State.lua",
    ["Services/Raid/Capabilities"] = "Services\\Raid\\Capabilities.lua",
    ["Services/Raid/Counts"] = "Services\\Raid\\Counts.lua",
    ["Services/Raid/Roster"] = "Services\\Raid\\Roster.lua",
    ["Services/Raid/Attendance"] = "Services\\Raid\\Attendance.lua",
    ["Services/Raid/LootRecords"] = "Services\\Raid\\LootRecords.lua",
    ["Services/Raid/Session"] = "Services\\Raid\\Session.lua",
    ["Services/Rolls/Countdown"] = "Services\\Rolls\\Countdown.lua",
    ["Services/Rolls/Sessions"] = "Services\\Rolls\\Sessions.lua",
    ["Services/Rolls/History"] = "Services\\Rolls\\History.lua",
    ["Services/Rolls/Responses"] = "Services\\Rolls\\Responses.lua",
    ["Services/Rolls/Resolution"] = "Services\\Rolls\\Resolution.lua",
    ["Services/Rolls/Display"] = "Services\\Rolls\\Display.lua",
    ["Services/Rolls/Service"] = "Services\\Rolls\\Service.lua",
    ["Services/Debug"] = "Services\\Debug.lua",
    ["Services/Reserves/Import"] = "Services\\Reserves\\Import.lua",
    ["Services/Reserves/Display"] = "Services\\Reserves\\Display.lua",
    ["Services/Reserves/Sync"] = "Services\\Reserves\\Sync.lua",
    ["Services/Reserves"] = "Services\\Reserves.lua",
    ["Services/Reserves/Chat"] = "Services\\Reserves\\Chat.lua",
    ["Services/Logger/Store"] = "Services\\Logger\\Store.lua",
    ["Services/Logger/View"] = "Services\\Logger\\View.lua",
    ["Services/Logger/Export"] = "Services\\Logger\\Export.lua",
    ["Services/Logger/Helpers"] = "Services\\Logger\\Helpers.lua",
    ["Services/Logger/Actions"] = "Services\\Logger\\Actions.lua",
    ["Controllers/Master"] = "Controllers\\Master.lua",
    ["Controllers/Logger"] = "Controllers\\Logger.lua",
    ["Controllers/Warnings"] = "Controllers\\Warnings.lua",
    ["Controllers/Spammer"] = "Controllers\\Spammer.lua",
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
    assertContains(source, "local registry = addon.ModuleRegistry", expected.name .. " must use direct registry lookup")
    assertContains(source, 'registry.SetLoaded("' .. expected.name .. '")', expected.name .. " must mark module loaded")
    assertNotContains(source, "ModuleRegistryPendingRegistrations", expected.name .. " must not use pending fallback")

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

local widgetPaths = {
    Config = "!KRT/Widgets/Config.lua",
    LootCounter = "!KRT/Widgets/LootCounter.lua",
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
    local message = context .. " must expose " .. methodName .. " = function"
    assert(source:find(pattern), message)
end

local function assertControllerDispatchPair(controllerName, methodName, sourcePath)
    local controllerPath = controllerPaths[controllerName]
    assert(controllerPath, sourcePath .. " dispatches unknown controller: " .. controllerName)

    local controllerSource = read(controllerPath)
    local context = sourcePath .. " -> " .. controllerName .. ":" .. methodName

    if scaffoldControllerMethods[methodName] then
        local message = context .. " must be backed by UIScaffold.DefineModuleUi"
        assertContains(controllerSource, "UIScaffold.DefineModuleUi({", message)
    else
        assertModuleMethod(controllerSource, methodName, context)
    end
end

local function assertControllerDispatchContracts()
    local sources = {
        "!KRT/EntryPoints/SlashEvents.lua",
        "!KRT/EntryPoints/Minimap.lua",
    }
    local dispatchPattern = 'Database%.RequestControllerMethod%("([%w_]+)"%s*,%s*"([%w_]+)"'
    local total = 0

    for i = 1, #sources do
        local sourcePath = sources[i]
        local source = read(sourcePath)
        local count = 0

        for controllerName, methodName in source:gmatch(dispatchPattern) do
            assertControllerDispatchPair(controllerName, methodName, sourcePath)
            count = count + 1
            total = total + 1
        end

        assert(count > 0, sourcePath .. " must contain literal controller dispatch pairs")
    end

    assert(total > 0, "controller dispatch sweep must find literal dispatch pairs")
end

local function assertWidgetDispatchPair(widgetId, methodName, sourcePath)
    local widgetPath = widgetPaths[widgetId]
    assert(widgetPath, sourcePath .. " dispatches unknown widget: " .. widgetId)

    local widgetSource = read(widgetPath)
    local context = sourcePath .. " -> " .. widgetId .. ":" .. methodName

    if standardWidgetMethods[methodName] then
        local message = context .. " must be backed by UIScaffold.MakeStandardWidgetApi"
        assertContains(widgetSource, "UIScaffold.MakeStandardWidgetApi(module,", message)
    else
        assertWidgetMethod(widgetSource, methodName, context)
    end
end

local function assertWidgetDispatchContracts()
    local scans = {
        {
            path = "!KRT/EntryPoints/SlashEvents.lua",
            pattern = 'callWidget%("([%w_]+)"%s*,%s*"([%w_]+)"',
            required = true,
        },
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            pattern = 'callWidgetMethod%("([%w_]+)"%s*,%s*"([%w_]+)"',
            required = true,
        },
        {
            path = "!KRT/Controllers/Master.lua",
            pattern = 'UIFacade:Call%("([%w_]+)"%s*,%s*"([%w_]+)"',
        },
        {
            path = "!KRT/EntryPoints/Minimap.lua",
            pattern = 'UIFacade:Call%("([%w_]+)"%s*,%s*"([%w_]+)"',
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
    local lootHistoryDispatch = 'Database.RequestControllerMethod("Logger", "ToggleLootHistory")'
    local raidAttendanceDispatch = 'Database.RequestControllerMethod("Logger", "ToggleRaidAttendance")'

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
assertSyncerDispatchContracts()
assertMasterWowForwardedContracts()

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
registerList(expectedEntryPoints)
registerList(expectedRollServices)
registerList(expectedDebugServices)
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
