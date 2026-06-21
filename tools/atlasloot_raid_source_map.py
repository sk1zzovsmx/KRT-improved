MODE_NORMAL_10 = "normal10"
MODE_NORMAL_20 = "normal20"
MODE_NORMAL_25 = "normal25"
MODE_NORMAL_40 = "normal40"
MODE_HEROIC_10 = "heroic10"
MODE_HEROIC_25 = "heroic25"


def source(name, npc_id, kind="boss"):
    return {"name": name, "npc_id": npc_id, "kind": kind}


def entry(expansion, atlas_key, raid, sources, mode, row_min=None, row_max=None):
    if isinstance(sources, dict):
        sources = [sources]
    result = {
        "expansion": expansion,
        "atlas_key": atlas_key,
        "raid": raid,
        "sources": sources,
        "mode": mode,
    }
    if row_min is not None:
        result["row_min"] = row_min
    if row_max is not None:
        result["row_max"] = row_max
    return result


MC_BOSSES = [
    source("Lucifron", 12118),
    source("Magmadar", 11982),
    source("Gehennas", 12259),
    source("Garr", 12057),
    source("Shazzrah", 12264),
    source("Baron Geddon", 12056),
    source("Golemagg the Incinerator", 11988),
    source("Sulfuron Harbinger", 12098),
    source("Majordomo Executus", 12018),
    source("Ragnaros", 11502),
]

EDGE_OF_MADNESS = [
    source("Gri'lek", 15082),
    source("Hazza'rah", 15083),
    source("Renataki", 15084),
    source("Wushoolay", 15085),
]

ZG_BOSSES = [
    source("High Priestess Jeklik", 14517),
    source("High Priest Venoxis", 14507),
    source("High Priestess Mar'li", 14510),
    source("Bloodlord Mandokir", 11382),
    source("High Priest Thekal", 14509),
    source("High Priestess Arlokk", 14515),
    source("Jin'do the Hexxer", 11380),
    source("Hakkar", 14834),
    source("Gahz'ranka", 15114),
] + EDGE_OF_MADNESS

BUG_TRIO = [
    source("Bug Trio", 15511),
    source("Bug Trio", 15543),
    source("Bug Trio", 15544),
]

KARA_OPERA = [
    source("Dorothee", 17535),
    source("The Crone", 18168),
    source("Romulo", 17533),
    source("Julianne", 17534),
    source("The Big Bad Wolf", 17521),
]

ESSENCE_OF_SOULS = [
    source("Essence of Anger", 23420),
    source("Essence of Desire", 23419),
    source("Essence of Suffering", 23418),
]

EREDAR_TWINS = [
    source("Grand Warlock Alythess", 25166),
    source("Lady Sacrolash", 25165),
]

FOUR_HORSEMEN = [
    source("Highlord Mograine", 16062),
    source("Lady Blaumeux", 16065),
    source("Sir Zeliek", 16063),
    source("Thane Korth'azz", 16064),
]

IRON_COUNCIL = [
    source("Runemaster Molgeim", 32927),
    source("Steelbreaker", 32867),
    source("Stormcaller Brundir", 32857),
]

NORTHREND_BEASTS = [
    source("Acidmaw", 35144),
    source("Dreadscale", 34799),
    source("Gormok", 34796),
    source("Icehowl", 34797),
]

FACTION_CHAMPIONS = [
    source("Alyssia Moonstalker", 34467),
    source("Anthar Forgemender", 34466),
    source("Baelnor Lightbearer", 34471),
    source("Birana Stormhoof", 34451),
    source("Brienna Nightfell", 34473),
    source("Broln Stouthorn", 34455),
    source("Caiphus the Stern", 34447),
    source("Erin Misthoof", 34459),
    source("Ginselle Blightslinger", 34449),
    source("Gorgrim Shadowcleave", 34458),
    source("Harkzog", 34450),
    source("Irieth Shadowstep", 34472),
    source("Kavina Grovesong", 34460),
    source("Liandra Suncaller", 34445),
    source("Malithas Brightblade", 34456),
    source("Maz'dinah", 34454),
    source("Melador Valestrider", 34469),
    source("Narrhok Steelbreaker", 34453),
    source("Noozle Whizzlestick", 34468),
    source("Ruj'kah", 34448),
    source("Saamul", 34470),
    source("Serissa Grimdabbler", 34474),
    source("Shaabad", 34463),
    source("Shocuul", 34475),
    source("Thrakgar", 34444),
    source("Tyrius Duskblade", 34461),
    source("Velanaa", 34465),
    source("Vivienne Blackwhisper", 34441),
]

TWIN_VALKYRS = [
    source("Eydis Darkbane", 34496),
    source("Fjola Lightbane", 34497),
]

BLOOD_PRINCE_COUNCIL = [
    source("Prince Keleseth", 37972),
    source("Prince Taldaram", 37973),
    source("Prince Valanar", 37970),
]

DRAGON_OF_NIGHTMARE_ZONES = [
    "Ashenvale",
    "Duskwood",
    "Feralas",
    "The Hinterlands",
]


SOURCES = [
    # Vanilla raid instances.
    entry("Vanilla", "AQ20Kurinnaxx", "Ruins of Ahn'Qiraj", source("Kurinnaxx", 15348), MODE_NORMAL_20),
    entry("Vanilla", "AQ20Rajaxx", "Ruins of Ahn'Qiraj", source("General Rajaxx", 15341), MODE_NORMAL_20),
    entry("Vanilla", "AQ20Moam", "Ruins of Ahn'Qiraj", source("Moam", 15340), MODE_NORMAL_20),
    entry("Vanilla", "AQ20Buru", "Ruins of Ahn'Qiraj", source("Buru the Gorger", 15370), MODE_NORMAL_20),
    entry("Vanilla", "AQ20Ayamiss", "Ruins of Ahn'Qiraj", source("Ayamiss the Hunter", 15369), MODE_NORMAL_20),
    entry("Vanilla", "AQ20Ossirian", "Ruins of Ahn'Qiraj", source("Ossirian the Unscarred", 15339), MODE_NORMAL_20),
    entry("Vanilla", "AQ40Skeram", "Temple of Ahn'Qiraj", source("The Prophet Skeram", 15263), MODE_NORMAL_40),
    entry("Vanilla", "AQ40Vem", "Temple of Ahn'Qiraj", BUG_TRIO, MODE_NORMAL_40),
    entry("Vanilla", "AQ40Sartura", "Temple of Ahn'Qiraj", source("Battleguard Sartura", 15516), MODE_NORMAL_40),
    entry("Vanilla", "AQ40Fankriss", "Temple of Ahn'Qiraj", source("Fankriss the Unyielding", 15510), MODE_NORMAL_40),
    entry("Vanilla", "AQ40Viscidus", "Temple of Ahn'Qiraj", source("Viscidus", 15299), MODE_NORMAL_40),
    entry("Vanilla", "AQ40Huhuran", "Temple of Ahn'Qiraj", source("Princess Huhuran", 15509), MODE_NORMAL_40),
    entry(
        "Vanilla",
        "AQ40Emperors",
        "Temple of Ahn'Qiraj",
        [source("Emperor Vek'lor", 15276), source("Emperor Vek'nilash", 15275)],
        MODE_NORMAL_40,
    ),
    entry("Vanilla", "AQ40Ouro", "Temple of Ahn'Qiraj", source("Ouro", 15517), MODE_NORMAL_40),
    entry("Vanilla", "AQ40CThun", "Temple of Ahn'Qiraj", source("C'Thun", 15727), MODE_NORMAL_40),
    entry("Vanilla", "MCLucifron", "Molten Core", source("Lucifron", 12118), MODE_NORMAL_40),
    entry("Vanilla", "MCMagmadar", "Molten Core", source("Magmadar", 11982), MODE_NORMAL_40),
    entry("Vanilla", "MCGehennas", "Molten Core", source("Gehennas", 12259), MODE_NORMAL_40),
    entry("Vanilla", "MCGarr", "Molten Core", source("Garr", 12057), MODE_NORMAL_40),
    entry("Vanilla", "MCShazzrah", "Molten Core", source("Shazzrah", 12264), MODE_NORMAL_40),
    entry("Vanilla", "MCGeddon", "Molten Core", source("Baron Geddon", 12056), MODE_NORMAL_40),
    entry("Vanilla", "MCGolemagg", "Molten Core", source("Golemagg the Incinerator", 11988), MODE_NORMAL_40),
    entry("Vanilla", "MCSulfuron", "Molten Core", source("Sulfuron Harbinger", 12098), MODE_NORMAL_40),
    entry("Vanilla", "MCMajordomo", "Molten Core", source("Majordomo Executus", 12018), MODE_NORMAL_40),
    entry("Vanilla", "MCRagnaros", "Molten Core", source("Ragnaros", 11502), MODE_NORMAL_40),
    entry("Vanilla", "MCRANDOMBOSSDROPPS", "Molten Core", MC_BOSSES, MODE_NORMAL_40),
    entry("Vanilla", "BWLRazorgore", "Blackwing Lair", source("Razorgore the Untamed", 12435), MODE_NORMAL_40),
    entry("Vanilla", "BWLVaelastrasz", "Blackwing Lair", source("Vaelastrasz the Corrupt", 13020), MODE_NORMAL_40),
    entry("Vanilla", "BWLLashlayer", "Blackwing Lair", source("Broodlord Lashlayer", 12017), MODE_NORMAL_40),
    entry("Vanilla", "BWLFiremaw", "Blackwing Lair", source("Firemaw", 11983), MODE_NORMAL_40),
    entry("Vanilla", "BWLEbonroc", "Blackwing Lair", source("Ebonroc", 14601), MODE_NORMAL_40),
    entry("Vanilla", "BWLFlamegor", "Blackwing Lair", source("Flamegor", 11981), MODE_NORMAL_40),
    entry("Vanilla", "BWLChromaggus", "Blackwing Lair", source("Chromaggus", 14020), MODE_NORMAL_40),
    entry("Vanilla", "BWLNefarian1", "Blackwing Lair", source("Nefarian", 11583), MODE_NORMAL_40),
    entry("Vanilla", "BWLNefarian2", "Blackwing Lair", source("Nefarian", 11583), MODE_NORMAL_40),
    entry("Vanilla", "ZGJeklik", "Zul'Gurub", source("High Priestess Jeklik", 14517), MODE_NORMAL_20),
    entry("Vanilla", "ZGVenoxis", "Zul'Gurub", source("High Priest Venoxis", 14507), MODE_NORMAL_20),
    entry("Vanilla", "ZGMarli", "Zul'Gurub", source("High Priestess Mar'li", 14510), MODE_NORMAL_20),
    entry("Vanilla", "ZGMandokir", "Zul'Gurub", source("Bloodlord Mandokir", 11382), MODE_NORMAL_20),
    entry("Vanilla", "ZGEdgeofMadness", "Zul'Gurub", EDGE_OF_MADNESS, MODE_NORMAL_20),
    entry("Vanilla", "ZGGahzranka", "Zul'Gurub", source("Gahz'ranka", 15114), MODE_NORMAL_20),
    entry("Vanilla", "ZGThekal", "Zul'Gurub", source("High Priest Thekal", 14509), MODE_NORMAL_20),
    entry("Vanilla", "ZGArlokk", "Zul'Gurub", source("High Priestess Arlokk", 14515), MODE_NORMAL_20),
    entry("Vanilla", "ZGJindo", "Zul'Gurub", source("Jin'do the Hexxer", 11380), MODE_NORMAL_20),
    entry("Vanilla", "ZGHakkar", "Zul'Gurub", source("Hakkar", 14834), MODE_NORMAL_20),
    entry("Vanilla", "ZGMuddyChurningWaters", "Zul'Gurub", source("Gahz'ranka", 15114), MODE_NORMAL_20),
    entry("Vanilla", "ZGShared", "Zul'Gurub", ZG_BOSSES, MODE_NORMAL_20),
    entry("Vanilla", "WorldBossesClassic", "Azshara", source("Azuregos", 6109), MODE_NORMAL_40),
    # The Burning Crusade raid instances.
    entry("BurningCrusade", "BTNajentus", "Black Temple", source("High Warlord Naj'entus", 22887), MODE_NORMAL_25),
    entry("BurningCrusade", "BTSupremus", "Black Temple", source("Supremus", 22898), MODE_NORMAL_25),
    entry("BurningCrusade", "BTAkama", "Black Temple", source("Shade of Akama", 22841), MODE_NORMAL_25),
    entry("BurningCrusade", "BTGorefiend", "Black Temple", source("Teron Gorefiend", 22871), MODE_NORMAL_25),
    entry("BurningCrusade", "BTBloodboil", "Black Temple", source("Gurtogg Bloodboil", 22948), MODE_NORMAL_25),
    entry("BurningCrusade", "BTEssencofSouls", "Black Temple", ESSENCE_OF_SOULS, MODE_NORMAL_25),
    entry("BurningCrusade", "BTShahraz", "Black Temple", source("Mother Shahraz", 22947), MODE_NORMAL_25),
    entry("BurningCrusade", "BTCouncil", "Black Temple", source("Illidari Council", 23426), MODE_NORMAL_25),
    entry("BurningCrusade", "BTIllidanStormrage", "Black Temple", source("Illidan Stormrage", 22917), MODE_NORMAL_25),
    entry("BurningCrusade", "MountHyjalWinterchill", "Hyjal Summit", source("Rage Winterchill", 17767), MODE_NORMAL_25),
    entry("BurningCrusade", "MountHyjalAnetheron", "Hyjal Summit", source("Anetheron", 17808), MODE_NORMAL_25),
    entry("BurningCrusade", "MountHyjalKazrogal", "Hyjal Summit", source("Kaz'rogal", 17888), MODE_NORMAL_25),
    entry("BurningCrusade", "MountHyjalAzgalor", "Hyjal Summit", source("Azgalor", 17842), MODE_NORMAL_25),
    entry("BurningCrusade", "MountHyjalArchimonde", "Hyjal Summit", source("Archimonde", 17968), MODE_NORMAL_25),
    entry(
        "BurningCrusade",
        "CFRSerpentHydross",
        "Serpentshrine Cavern",
        source("Hydross the Unstable", 21216),
        MODE_NORMAL_25,
    ),
    entry(
        "BurningCrusade",
        "CFRSerpentLurker",
        "Serpentshrine Cavern",
        source("The Lurker Below", 21217),
        MODE_NORMAL_25,
    ),
    entry(
        "BurningCrusade",
        "CFRSerpentLeotheras",
        "Serpentshrine Cavern",
        source("Leotheras the Blind", 21215),
        MODE_NORMAL_25,
    ),
    entry(
        "BurningCrusade",
        "CFRSerpentKarathress",
        "Serpentshrine Cavern",
        source("Fathom-Lord Karathress", 21214),
        MODE_NORMAL_25,
    ),
    entry(
        "BurningCrusade",
        "CFRSerpentMorogrim",
        "Serpentshrine Cavern",
        source("Morogrim Tidewalker", 21213),
        MODE_NORMAL_25,
    ),
    entry("BurningCrusade", "CFRSerpentVashj", "Serpentshrine Cavern", source("Lady Vashj", 21212), MODE_NORMAL_25),
    entry(
        "BurningCrusade",
        "GruulsLairHighKingMaulgar",
        "Gruul's Lair",
        source("High King Maulgar", 18831),
        MODE_NORMAL_25,
    ),
    entry("BurningCrusade", "GruulGruul", "Gruul's Lair", source("Gruul the Dragonkiller", 19044), MODE_NORMAL_25),
    entry("BurningCrusade", "HCMagtheridon", "Magtheridon's Lair", source("Magtheridon", 17257), MODE_NORMAL_25),
    entry("BurningCrusade", "KaraAttumen", "Karazhan", source("Attumen the Huntsman", 15550), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraMoroes", "Karazhan", source("Moroes", 15687), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraMaiden", "Karazhan", source("Maiden of Virtue", 16457), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraOperaEvent", "Karazhan", KARA_OPERA, MODE_NORMAL_10),
    entry("BurningCrusade", "KaraCurator", "Karazhan", source("The Curator", 15691), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraIllhoof", "Karazhan", source("Terestian Illhoof", 15688), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraAran", "Karazhan", source("Shade of Aran", 16524), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraNetherspite", "Karazhan", source("Netherspite", 15689), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraNightbane", "Karazhan", source("Nightbane", 17225), MODE_NORMAL_10),
    entry("BurningCrusade", "KaraPrince", "Karazhan", source("Prince Malchezaar", 15690), MODE_NORMAL_10),
    entry("BurningCrusade", "SPKalecgos", "Sunwell Plateau", source("Kalecgos", 24891), MODE_NORMAL_25),
    entry("BurningCrusade", "SPBrutallus", "Sunwell Plateau", source("Brutallus", 24882), MODE_NORMAL_25),
    entry("BurningCrusade", "SPFelmyst", "Sunwell Plateau", source("Felmyst", 25038), MODE_NORMAL_25),
    entry("BurningCrusade", "SPEredarTwins", "Sunwell Plateau", EREDAR_TWINS, MODE_NORMAL_25),
    entry("BurningCrusade", "SPMuru", "Sunwell Plateau", source("M'uru", 25741), MODE_NORMAL_25),
    entry("BurningCrusade", "SPKiljaeden", "Sunwell Plateau", source("Kil'jaeden", 25315), MODE_NORMAL_25),
    entry("BurningCrusade", "TKEyeAlar", "The Eye", source("Al'ar", 19514), MODE_NORMAL_25),
    entry("BurningCrusade", "TKEyeVoidReaver", "The Eye", source("Void Reaver", 19516), MODE_NORMAL_25),
    entry("BurningCrusade", "TKEyeSolarian", "The Eye", source("High Astromancer Solarian", 18805), MODE_NORMAL_25),
    entry("BurningCrusade", "TKEyeKaelthas", "The Eye", source("Kael'thas Sunstrider", 19622), MODE_NORMAL_25),
    entry("BurningCrusade", "ZANalorakk", "Zul'Aman", source("Nalorakk", 23576), MODE_NORMAL_10),
    entry("BurningCrusade", "ZAAkilZon", "Zul'Aman", source("Akil'zon", 23574), MODE_NORMAL_10),
    entry("BurningCrusade", "ZAJanAlai", "Zul'Aman", source("Jan'alai", 23578), MODE_NORMAL_10),
    entry("BurningCrusade", "ZAHalazzi", "Zul'Aman", source("Halazzi", 23577), MODE_NORMAL_10),
    entry("BurningCrusade", "ZAMalacrass", "Zul'Aman", source("Hex Lord Malacrass", 24239), MODE_NORMAL_10),
    entry("BurningCrusade", "ZAZuljin", "Zul'Aman", source("Zul'jin", 23863), MODE_NORMAL_10),
    entry(
        "BurningCrusade",
        "WorldBossesBC",
        "Hellfire Peninsula",
        source("Doom Lord Kazzak", 18728),
        MODE_NORMAL_40,
        row_min=2,
        row_max=11,
    ),
    entry(
        "BurningCrusade",
        "WorldBossesBC",
        "Shadowmoon Valley",
        source("Doomwalker", 17711),
        MODE_NORMAL_40,
        row_min=17,
        row_max=26,
    ),
]


for dragon_key, dragon_source in (
    ("DEmeriss", source("Emeriss", 14889)),
    ("DLethon", source("Lethon", 14888)),
    ("DTaerar", source("Taerar", 14890)),
    ("DYsondre", source("Ysondre", 14887)),
):
    for dragon_zone in DRAGON_OF_NIGHTMARE_ZONES:
        SOURCES.append(entry("Vanilla", dragon_key, dragon_zone, dragon_source, MODE_NORMAL_40))


def add_wrath_key(entries, atlas_key, raid, sources, mode):
    entries.append(entry("Wrath", atlas_key, raid, sources, mode))


def build_wrath_sources():
    entries = []

    for boss_key, boss_source in (
        ("Archavon", source("Archavon the Stone Watcher", 31125)),
        ("Emalon", source("Emalon the Storm Watcher", 33993)),
        ("Koralon", source("Koralon the Flame Watcher", 35013)),
        ("Toravon", source("Toravon the Ice Watcher", 38433)),
    ):
        variants = ("",)
        if boss_key == "Koralon":
            variants = ("_A", "_H")
        for variant in variants:
            max_tab = 7 if boss_key == "Archavon" else 8
            for idx in range(1, max_tab + 1):
                add_wrath_key(
                    entries,
                    "VaultofArchavon%s%d%s" % (boss_key, idx, variant),
                    "Vault of Archavon",
                    boss_source,
                    MODE_NORMAL_10,
                )
                add_wrath_key(
                    entries,
                    "VaultofArchavon%s%d25Man%s" % (boss_key, idx, variant),
                    "Vault of Archavon",
                    boss_source,
                    MODE_NORMAL_25,
                )

    naxx = [
        ("Patchwerk", source("Patchwerk", 16028)),
        ("Grobbulus", source("Grobbulus", 15931)),
        ("Gluth1", source("Gluth", 15932)),
        ("Gluth2", source("Gluth", 15932)),
        ("Thaddius", source("Thaddius", 15928)),
        ("AnubRekhan", source("Anub'Rekhan", 15956)),
        ("Faerlina", source("Grand Widow Faerlina", 15953)),
        ("Maexxna", source("Maexxna", 15952)),
        ("Razuvious", source("Instructor Razuvious", 16061)),
        ("Gothik", source("Gothik the Harvester", 16060)),
        ("FourHorsemen", FOUR_HORSEMEN),
        ("Noth", source("Noth the Plaguebringer", 15954)),
        ("Heigan", source("Heigan the Unclean", 15936)),
        ("Loatheb", source("Loatheb", 16011)),
        ("Sapphiron", source("Sapphiron", 15989)),
        ("KelThuzad", source("Kel'Thuzad", 15990)),
    ]
    for key, src in naxx:
        add_wrath_key(entries, "Naxx80" + key, "Naxxramas", src, MODE_NORMAL_10)
        add_wrath_key(entries, "Naxx80" + key + "25Man", "Naxxramas", src, MODE_NORMAL_25)

    add_wrath_key(entries, "Sartharion", "The Obsidian Sanctum", source("Sartharion", 28860), MODE_NORMAL_10)
    add_wrath_key(entries, "Sartharion25Man", "The Obsidian Sanctum", source("Sartharion", 28860), MODE_NORMAL_25)
    add_wrath_key(entries, "Malygos", "The Eye of Eternity", source("Malygos", 28859), MODE_NORMAL_10)
    add_wrath_key(entries, "Malygos25Man", "The Eye of Eternity", source("Malygos", 28859), MODE_NORMAL_25)

    ulduar = [
        ("Leviathan", source("Flame Leviathan", 33113)),
        ("Razorscale", source("Razorscale", 33186)),
        ("Ignis", source("Ignis the Furnace Master", 33118)),
        ("Deconstructor", source("XT-002 Deconstructor", 33293)),
        ("IronCouncil", IRON_COUNCIL),
        ("Kologarn", source("Kologarn", 32930)),
        ("Algalon", source("Algalon the Observer", 32871)),
        ("Auriaya", source("Auriaya", 33515)),
        ("Hodir", source("Hodir", 32845)),
        ("Thorim", source("Thorim", 32865)),
        ("Freya", source("Freya", 32906)),
        ("Mimiron", source("Mimiron", 33350)),
        ("Vezax", source("General Vezax", 33271)),
        ("YoggSaron", source("Yogg-Saron", 33288)),
    ]
    for key, src in ulduar:
        add_wrath_key(entries, "Ulduar" + key, "Ulduar", src, MODE_NORMAL_10)
        add_wrath_key(entries, "Ulduar" + key + "25Man", "Ulduar", src, MODE_NORMAL_25)

    trial = [
        ("NorthrendBeasts", NORTHREND_BEASTS),
        ("LordJaraxxus", source("Lord Jaraxxus", 34780)),
        ("FactionChampions", FACTION_CHAMPIONS),
        ("TwinValkyrs", TWIN_VALKYRS),
        ("Anubarak", source("Anub'arak", 34564)),
    ]
    for key, src in trial:
        for faction in ("_A", "_H"):
            add_wrath_key(entries, "TrialoftheCrusader" + key + faction, "Trial of the Crusader", src, MODE_NORMAL_10)
            add_wrath_key(
                entries,
                "TrialoftheCrusader" + key + "25Man" + faction,
                "Trial of the Crusader",
                src,
                MODE_NORMAL_25,
            )
            add_wrath_key(
                entries,
                "TrialoftheCrusader" + key + "HEROIC" + faction,
                "Trial of the Crusader",
                src,
                MODE_HEROIC_10,
            )
            add_wrath_key(
                entries,
                "TrialoftheCrusader" + key + "25ManHEROIC" + faction,
                "Trial of the Crusader",
                src,
                MODE_HEROIC_25,
            )

    for key, mode in (
        ("Onyxia_1", MODE_NORMAL_10),
        ("Onyxia_2", MODE_NORMAL_10),
        ("Onyxia_125Man", MODE_NORMAL_25),
        ("Onyxia_225Man", MODE_NORMAL_25),
    ):
        add_wrath_key(entries, key, "Onyxia's Lair", source("Onyxia", 10184), mode)

    icc = [
        ("LordMarrowgar", source("Lord Marrowgar", 36612)),
        ("LadyDeathwhisper", source("Lady Deathwhisper", 36855)),
        ("Saurfang", source("Deathbringer Saurfang", 37813)),
        ("Festergut", source("Festergut", 36626)),
        ("Rotface", source("Rotface", 36627)),
        ("Putricide", source("Professor Putricide", 36678)),
        ("Council", BLOOD_PRINCE_COUNCIL),
        ("Lanathel", source("Queen Lana'thel", 37955)),
        ("Valithria", source("Valithria Dreamwalker", 36789)),
        ("Sindragosa", source("Sindragosa", 36853)),
        ("LichKing", source("The Lich King", 36597)),
    ]
    for key, src in icc:
        add_wrath_key(entries, "ICC" + key, "Icecrown Citadel", src, MODE_NORMAL_10)
        add_wrath_key(entries, "ICC" + key + "25Man", "Icecrown Citadel", src, MODE_NORMAL_25)
        add_wrath_key(entries, "ICC" + key + "HEROIC", "Icecrown Citadel", src, MODE_HEROIC_10)
        add_wrath_key(entries, "ICC" + key + "25ManHEROIC", "Icecrown Citadel", src, MODE_HEROIC_25)

    for key, mode in (
        ("Halion", MODE_NORMAL_10),
        ("Halion25Man", MODE_NORMAL_25),
        ("HalionHEROIC", MODE_HEROIC_10),
        ("Halion25ManHEROIC", MODE_HEROIC_25),
    ):
        add_wrath_key(entries, key, "The Ruby Sanctum", source("Halion", 39863), mode)

    return entries


SOURCES.extend(build_wrath_sources())
