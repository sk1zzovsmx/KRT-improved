KRT_Raids = {
    {
        schemaVersion = 1,
        raidNid = "12",
        startTime = "1713000000",
        nextPlayerNid = 1,
        nextBossNid = 1,
        nextLootNid = 1,
        players = {
            { playerNid = 1, name = " Alpha ", class = "PALADIN", count = "3", rank = 0, subgroup = 1 },
            { playerNid = 1, name = "Beta", class = "", count = -2, rank = 1, subgroup = 2 },
            { name = "Gamma", class = "ROGUE", count = 0 },
        },
        bossKills = {
            {
                bossNid = 1,
                name = "Professor Putricide",
                difficulty = "4",
                players = { "Alpha", "Beta", "Beta", "Missing", 0 },
                attendanceMask = "legacy",
            },
        },
        loot = {
            {
                lootNid = 1,
                itemId = "50704",
                itemName = "Rigormortis",
                itemCount = 0,
                looter = "Beta",
                rollType = "1",
                rollValue = "100",
                bossNid = 1,
            },
            {
                lootNid = 1,
                itemId = 50735,
                itemName = "Oathbinder, Charge of the Ranger-General",
                looter = "Missing",
                rollType = 0,
                rollValue = 0,
                bossNid = 0,
            },
        },
        changes = {
            [" Alpha "] = " Holy ",
            Beta = "",
        },
        _playersByName = {},
        _runtime = {
            playersByName = {},
        },
    },
}

KRT_Reserves = {
    [" beta "] = {
        original = "Beta",
        reserves = {
            { rawID = 50704, itemName = "Rigormortis", quantity = 1, plus = 0, player = "Beta" },
        },
    },
}

KRT_Players = {}
KRT_Warnings = {}
KRT_Spammer = {}
KRT_Options = {}
