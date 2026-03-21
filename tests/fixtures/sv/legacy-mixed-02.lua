KRT_Raids = {
    {
        schemaVersion = 2,
        raidNid = 4,
        startTime = "1711000000",
        nextPlayerNid = 3,
        nextBossNid = 3,
        nextLootNid = 4,
        players = {
            { playerNid = 1, name = "TankOne", class = "WARRIOR", count = 0 },
            { playerNid = 2, name = "HealOne", class = "PRIEST", count = 1, join = "1711000010" },
        },
        bossKills = {
            { bossNid = 1, name = "Lord Marrowgar", players = { 1, "HealOne" }, mode = "h", difficulty = 4 },
            { bossNid = 2, name = "Lady Deathwhisper", players = { "TankOne", "HealOne" }, attendanceMask = 123 },
        },
        loot = {
            {
                lootNid = 1,
                itemId = 49981,
                itemLink = "|cff0070dd|Hitem:49981|h[Fallout Supercharger]|h|r",
                looter = "HealOne",
                bossNid = 2,
                itemCount = 1,
            },
            {
                lootNid = 2,
                itemId = 50348,
                itemName = "Frost Needle",
                looterNid = 2,
                rollType = 1,
                rollValue = 97,
                bossNid = 2,
            },
            {
                lootNid = 3,
                itemId = 50426,
                itemName = "Heaven's Fall, Kryss of a Thousand Lies",
                looter = "UnknownPlayer",
                bossNid = 2,
                rollType = 0,
                rollValue = 0,
            },
        },
        changes = {
            TankOne = "Arms",
            HealOne = "Holy",
        },
        _playersByName = {},
    },
    {
        schemaVersion = 3,
        raidNid = 9,
        startTime = 1712000000,
        players = {
            { playerNid = 1, name = "Ferra", class = "MAGE", count = 4, rank = 0, subgroup = 1 },
        },
        bossKills = {},
        loot = {
            {
                lootNid = 1,
                itemId = 50675,
                itemName = "Aldriana's Gloves of Secrecy",
                looterNid = 1,
                itemCount = 1,
                rollType = 0,
                rollValue = 0,
            },
        },
        changes = {},
        nextPlayerNid = 2,
        nextBossNid = 1,
        nextLootNid = 2,
    },
}

KRT_Reserves = {
    ferra = {
        playerNameDisplay = "Ferra",
        reserves = {
            { rawID = 50675, itemName = "Aldriana's Gloves of Secrecy", quantity = 1, plus = 0 },
        },
    },
    [" healone "] = {
        original = "HealOne",
        reserves = {
            { rawID = 49981, itemName = "Fallout Supercharger", quantity = 1, plus = 1, player = "HealOne" },
            { rawID = 50348, itemName = "Frost Needle", quantity = 2, plus = 0, player = "HealOne" },
        },
    },
}

KRT_Players = {}
KRT_Warnings = {}
KRT_Spammer = {}
KRT_Options = {}
