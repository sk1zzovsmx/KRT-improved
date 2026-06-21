#!/usr/bin/env python3
"""Generate KRT raid and world-boss loot source shards from AtlasLoot reference tables.

AtlasLoot is used as a build-time completeness reference. The generated addon
data remains KRT-native and does not require AtlasLoot at runtime.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.request
from collections import OrderedDict

from atlasloot_raid_source_map import SOURCES


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
DATASET_DIR = REPO_ROOT / "!KRT" / "Modules" / "Dataset" / "LootSources"

EXPANSION_FILES = OrderedDict(
    [
        ("Vanilla", DATASET_DIR / "Vanilla.lua"),
        ("BurningCrusade", DATASET_DIR / "BurningCrusade.lua"),
        ("Wrath", DATASET_DIR / "Wrath.lua"),
    ]
)

ATLAS_FILES = {
    "Vanilla": {
        "relative": pathlib.Path("AtlasLoot_OriginalWoW") / "originalwow.lua",
        "url": (
            "https://raw.githubusercontent.com/Plan414/World-of-Warcraft-3.3.5-Addons/"
            "main/AtlasLoot%20Package/AtlasLoot_OriginalWoW/originalwow.lua"
        ),
    },
    "BurningCrusade": {
        "relative": pathlib.Path("AtlasLoot_BurningCrusade") / "burningcrusade.lua",
        "url": (
            "https://raw.githubusercontent.com/Plan414/World-of-Warcraft-3.3.5-Addons/"
            "main/AtlasLoot%20Package/AtlasLoot_BurningCrusade/burningcrusade.lua"
        ),
    },
    "Wrath": {
        "relative": pathlib.Path("AtlasLoot_WrathoftheLichKing") / "wrathofthelichking.lua",
        "url": (
            "https://raw.githubusercontent.com/Plan414/World-of-Warcraft-3.3.5-Addons/"
            "main/AtlasLoot%20Package/AtlasLoot_WrathoftheLichKing/wrathofthelichking.lua"
        ),
    },
}

MODE_NAMES = {
    frozenset(["normal10"]): "N10",
    frozenset(["normal20"]): "N20",
    frozenset(["normal25"]): "N25",
    frozenset(["normal40"]): "N40",
    frozenset(["heroic10"]): "H10",
    frozenset(["heroic25"]): "H25",
    frozenset(["normal10", "normal25"]): "N10_N25",
    frozenset(["normal25", "heroic25"]): "N25_H25",
    frozenset(["normal10", "normal25", "heroic10", "heroic25"]): "ALL_10_25",
}

MODE_ORDER = ["normal10", "normal20", "normal25", "normal40", "heroic10", "heroic25"]

HEADER_BY_EXPANSION = {
    "Vanilla": ("Classic Vanilla", "Vanilla expansion dataset"),
    "BurningCrusade": ("The Burning Crusade", "Burning Crusade dataset"),
    "Wrath": ("Wrath of the Lich King", "Wrath of the Lich King dataset"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--atlasloot-root",
        type=pathlib.Path,
        help="Path to the AtlasLoot Package directory from the Plan414 repository.",
    )
    parser.add_argument(
        "--no-download",
        action="store_true",
        help="Require --atlasloot-root files and do not download raw GitHub sources.",
    )
    return parser.parse_args()


def normalize_path(path: pathlib.Path) -> str:
    return str(path).replace("\\", "/")


def load_existing_dataset() -> OrderedDict:
    lua_exe = shutil.which(os.environ.get("LUA", "lua"))
    if not lua_exe:
        raise RuntimeError("lua executable not found; set LUA to the Lua 5.1/LuaJIT command")

    script = r"""
local addon = {}
addon.Database = {}
local feature = {}
function addon.Database.GetFeatureShared()
    return feature
end
feature.LootSourcesData = {}
for _, file in ipairs({
    "!KRT/Modules/Dataset/LootSources/Vanilla.lua",
    "!KRT/Modules/Dataset/LootSources/BurningCrusade.lua",
    "!KRT/Modules/Dataset/LootSources/Wrath.lua",
}) do
    local chunk, err = loadfile(file)
    if not chunk then error(err) end
    chunk("!KRT", addon)
end
local raw = addon.LootSourcesData.Raw or {}
for i = 1, #raw do
    local raid = raw[i]
    local sources = raid.sources or {}
    for j = 1, #sources do
        local source = sources[j]
        local items = source.items or {}
        for k = 1, #items do
            local item = items[k]
            local modes = item[2] or {}
            local modeNames = {}
            for mode in pairs(modes) do
                modeNames[#modeNames + 1] = mode
            end
            table.sort(modeNames)
            print(table.concat({
                raid.name or "",
                source.name or "",
                tostring(source.npcId or ""),
                tostring(source.kind or "boss"),
                tostring(item[1] or ""),
                table.concat(modeNames, ",")
            }, "\t"))
        end
    end
end
"""
    result = subprocess.run(
        [lua_exe, "-"],
        input=script,
        cwd=str(REPO_ROOT),
        text=True,
        encoding="utf-8",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("failed to load current KRT dataset through lua:\n" + result.stderr)

    data: OrderedDict[str, OrderedDict] = OrderedDict((key, OrderedDict()) for key in EXPANSION_FILES)
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        raid, name, npc_id_text, kind, item_id_text, modes_text = line.split("\t")
        expansion = infer_expansion(raid, modes_text)
        add_item(data, expansion, raid, name, int(npc_id_text), kind, int(item_id_text), modes_text.split(","))
    return data


def infer_expansion(raid: str, modes_text: str) -> str:
    if raid in {
        "Karazhan",
        "Gruul's Lair",
        "Magtheridon's Lair",
        "Serpentshrine Cavern",
        "The Eye",
        "Hyjal Summit",
        "Black Temple",
        "Zul'Aman",
        "Sunwell Plateau",
        "Hellfire Peninsula",
        "Shadowmoon Valley",
    }:
        return "BurningCrusade"
    if raid in {
        "The Obsidian Sanctum",
        "The Eye of Eternity",
        "Vault of Archavon",
        "Ulduar",
        "Trial of the Crusader",
        "Icecrown Citadel",
        "The Ruby Sanctum",
    }:
        return "Wrath"
    if raid == "Onyxia's Lair":
        return "Vanilla" if modes_text == "normal40" else "Wrath"
    if raid == "Naxxramas":
        return "Vanilla" if modes_text == "normal40" else "Wrath"
    return "Vanilla"


def source_key(name: str, npc_id: int, kind: str) -> tuple[str, int, str]:
    return name, int(npc_id), kind or "boss"


def add_item(
    data: OrderedDict,
    expansion: str,
    raid: str,
    source_name: str,
    npc_id: int,
    kind: str,
    item_id: int,
    modes: list[str],
) -> None:
    if item_id <= 0 or npc_id <= 0:
        return
    raid_bucket = data.setdefault(expansion, OrderedDict()).setdefault(raid, OrderedDict())
    key = source_key(source_name, npc_id, kind)
    source_bucket = raid_bucket.setdefault(
        key,
        {
            "name": source_name,
            "npc_id": npc_id,
            "kind": kind or "boss",
            "items": OrderedDict(),
        },
    )
    item_modes = source_bucket["items"].setdefault(item_id, set())
    for mode in modes:
        if mode:
            item_modes.add(mode)


def load_atlas_texts(args: argparse.Namespace) -> dict[str, str]:
    loaded = {}
    for expansion, spec in ATLAS_FILES.items():
        text = None
        if args.atlasloot_root:
            candidate = args.atlasloot_root / spec["relative"]
            if candidate.exists():
                text = candidate.read_text(encoding="utf-8", errors="ignore")
        if text is None:
            if args.no_download:
                raise FileNotFoundError("missing AtlasLoot source for " + expansion)
            with urllib.request.urlopen(spec["url"], timeout=30) as response:
                text = response.read().decode("utf-8", errors="ignore")
        loaded[expansion] = text
    return loaded


def parse_atlas_blocks(text: str) -> dict[str, list[dict[str, int]]]:
    blocks = {}
    pattern = re.compile(r'AtlasLoot_Data\["([^"]+)"\]\s*=\s*\{(.*?)\n\s*\};', re.S)
    row_pattern = re.compile(r"\{\s*(\d+)\s*,\s*(\d+)\s*,")
    for key, body in pattern.findall(text):
        rows = []
        for row_text, item_text in row_pattern.findall(body):
            item_id = int(item_text)
            if item_id > 0:
                rows.append(
                    {
                        "row": int(row_text),
                        "item_id": item_id,
                    }
                )
        blocks[key] = rows
    return blocks


def filter_block_item_ids(rows: list[dict[str, int]], spec: dict) -> list[int]:
    row_min = spec.get("row_min")
    row_max = spec.get("row_max")
    item_ids = []
    seen = set()
    for row in rows:
        row_index = row["row"]
        if row_min is not None and row_index < row_min:
            continue
        if row_max is not None and row_index > row_max:
            continue

        item_id = row["item_id"]
        if item_id > 0 and item_id not in seen:
            item_ids.append(item_id)
            seen.add(item_id)
    return item_ids


def apply_atlas_sources(data: OrderedDict, atlas_texts: dict[str, str]) -> tuple[int, list[str]]:
    blocks_by_expansion = {expansion: parse_atlas_blocks(text) for expansion, text in atlas_texts.items()}
    additions = 0
    missing_keys = []
    for spec in SOURCES:
        expansion = spec["expansion"]
        rows = blocks_by_expansion.get(expansion, {}).get(spec["atlas_key"])
        if rows is None:
            missing_keys.append(expansion + ":" + spec["atlas_key"])
            continue
        item_ids = filter_block_item_ids(rows, spec)
        for source in spec["sources"]:
            for item_id in item_ids:
                before = get_mode_count(data, expansion, spec["raid"], source, item_id)
                add_item(
                    data,
                    expansion,
                    spec["raid"],
                    source["name"],
                    source["npc_id"],
                    source.get("kind", "boss"),
                    item_id,
                    [spec["mode"]],
                )
                after = get_mode_count(data, expansion, spec["raid"], source, item_id)
                if after > before:
                    additions += 1
    return additions, missing_keys


def get_mode_count(data: OrderedDict, expansion: str, raid: str, source: dict, item_id: int) -> int:
    raid_bucket = data.get(expansion, {}).get(raid, {})
    bucket = raid_bucket.get(source_key(source["name"], source["npc_id"], source.get("kind", "boss")))
    if not bucket:
        return 0
    return len(bucket["items"].get(item_id, set()))


def mode_expression(modes: set[str]) -> str:
    frozen = frozenset(modes)
    if frozen in MODE_NAMES:
        return MODE_NAMES[frozen]
    parts = ["%s = true" % mode for mode in MODE_ORDER if mode in modes]
    return "{ " + ", ".join(parts) + " }"


def write_lua_file(expansion: str, path: pathlib.Path, raid_bucket: OrderedDict) -> None:
    expansion_note, dataset_name = HEADER_BY_EXPANSION[expansion]
    lines = [
        "-- ----- KRT Lua Contract ----- --",
        "-- deps: local addon = select(2, ...)",
        "-- shared: local feature = addon.Database.GetFeatureShared()",
        "-- exports: addon.LootSourcesData",
        "-- events: none",
        "-- notes: static raid loot source data for " + expansion_note,
        "",
        "local addon = select(2, ...)",
        "local feature = addon.Database.GetFeatureShared()",
        "",
        "local LootSourcesData = feature.LootSourcesData or {}",
        "addon.LootSourcesData = LootSourcesData",
        "LootSourcesData.Raw = LootSourcesData.Raw or {}",
        "",
        "-- ----- Internal state ----- --",
        "-- name: " + dataset_name,
        "",
        "local N10 = { normal10 = true }",
        "local N20 = { normal20 = true }",
        "local N25 = { normal25 = true }",
        "local N40 = { normal40 = true }",
        "local H10 = { heroic10 = true }",
        "local H25 = { heroic25 = true }",
        "local N10_N25 = { normal10 = true, normal25 = true }",
        "local N25_H25 = { heroic25 = true, normal25 = true }",
        "local ALL_10_25 = { heroic10 = true, heroic25 = true, normal10 = true, normal25 = true }",
        "",
        "-- ----- Private helpers ----- --",
        "local function appendLootSources(lootSources)",
        "    for i = 1, #lootSources do",
        "        LootSourcesData.Raw[#LootSourcesData.Raw + 1] = lootSources[i]",
        "    end",
        "end",
        "",
        "-- ----- Public methods ----- --",
        "appendLootSources({",
    ]

    for raid_name, sources in raid_bucket.items():
        lines.extend(
            [
                "    {",
                '        name = "%s",' % escape_lua_string(raid_name),
                "        sources = {",
            ]
        )
        for source in sources.values():
            lines.extend(
                [
                    "            {",
                    '                name = "%s",' % escape_lua_string(source["name"]),
                    "                npcId = %d," % source["npc_id"],
                ]
            )
            if source["kind"] != "boss":
                lines.append('                kind = "%s",' % escape_lua_string(source["kind"]))
            lines.append("                items = {")
            for item_id, modes in sorted(source["items"].items()):
                lines.append("                    { %d, %s }," % (item_id, mode_expression(modes)))
            lines.extend(
                [
                    "                },",
                    "            },",
                ]
            )
        lines.extend(
            [
                "        },",
                "    },",
            ]
        )
    lines.extend(
        [
            "})",
        ]
    )
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
        handle.write("\n")


def escape_lua_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    args = parse_args()
    data = load_existing_dataset()
    atlas_texts = load_atlas_texts(args)
    additions, missing_keys = apply_atlas_sources(data, atlas_texts)
    for expansion, path in EXPANSION_FILES.items():
        write_lua_file(expansion, path, data.get(expansion, OrderedDict()))
    print("AtlasLoot mapped item-mode additions: %d" % additions)
    if missing_keys:
        print("Missing mapped AtlasLoot keys: %d" % len(missing_keys), file=sys.stderr)
        for key in missing_keys:
            print("  " + key, file=sys.stderr)
        return 1
    for expansion, path in EXPANSION_FILES.items():
        print("%s -> %s" % (expansion, normalize_path(path.relative_to(REPO_ROOT))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
