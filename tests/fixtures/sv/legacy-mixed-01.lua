KRT_Raids = {
    {
        schemaVersion = 1,
        raidNid = "7",
        startTime = 1710000000,
        nextPlayerNid = 0,
        nextBossNid = 0,
        nextLootNid = 0,
        players = {
            { playerNid = 1, name = " Alice ", class = "Mage ", count = "2", rank = 0, subgroup = 1 },
            { playerNid = "2", name = "Bob", class = "", count = -5, rank = 1, subgroup = 2 },
        },
        bossKills = {
            {
                bossNid = 1,
                name = "Patchwerk",
                difficulty = 1,
                mode = "N",
                attendanceMask = "ff",
                players = { "Alice", 2, "MissingPlayer", 0 },
            },
        },
        loot = {
            {
                lootNid = 1,
                itemId = 45878,
                itemName = "Broken Promise",
                itemCount = 1,
                looter = "Alice",
                rollType = 0,
                rollValue = 0,
                bossNid = 1,
            },
            {
                lootNid = 2,
                itemId = 40627,
                itemName = "Gown of the Spell-Weaver",
                itemCount = 2,
                looter = 2,
                rollType = 1,
                rollValue = 99,
                bossNid = 99,
                attendanceMask = "legacy",
            },
        },
        changes = {
            [" Alice "] = " Frost ",
            [""] = "ShouldDrop",
            ["Bob"] = "",
        },
        _playersByName = {},
        _playerIdxByNid = {},
        _bossIdxByNid = {},
        _lootIdxByNid = {},
        _runtime = {
            playersByName = {},
        },
    },
}

KRT_Reserves = {
    [" Alice "] = {
        original = "Alice",
        reserves = {
            { rawID = 45878, itemName = "Broken Promise", quantity = 2, plus = 1, player = "Alice" },
            { itemName = "DroppedRowMissingRawID", player = "Alice" },
        },
    },
    ["alice"] = {
        playerNameDisplay = "?",
        reserves = {
            { rawID = 40627, itemName = "Gown of the Spell-Weaver", quantity = 1, plus = 0 },
        },
    },
}

KRT_Players = {}
KRT_Warnings = {}
KRT_Spammer = {}
KRT_Options = {}
