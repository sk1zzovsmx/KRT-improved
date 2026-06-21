#!/usr/bin/env python3
"""Build a local visual catalog for WotLK Interface BLP textures.

This tool converts locally extracted Blizzard BLP files to JPEG thumbnails and
generates an HTML gallery. The generated images are for local inspection only.
Do not commit or redistribute the generated catalog.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw


DEFAULT_SOURCE = Path.home() / "Desktop" / "WoW_Interface_AddOn_Kit_3.3.5a" / "Interface"
DEFAULT_OUTPUT = Path(".codex") / "local-interface-texture-catalog"
THUMB_SIZE = 160


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert local WoW Interface BLP files to a visual JPEG catalog.")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help="Path to an extracted Interface directory that contains .blp files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Output directory for local JPEG thumbnails and index.html.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Optional maximum number of BLP files to convert, for quick tests.",
    )
    return parser.parse_args()


def rel_interface_path(path: Path, source: Path) -> str:
    rel = path.relative_to(source).with_suffix("")
    return "Interface\\" + "\\".join(rel.parts)


def safe_stem(path: str) -> str:
    cleaned = []
    for ch in path:
        if ch.isalnum():
            cleaned.append(ch)
        else:
            cleaned.append("_")
    stem = "".join(cleaned).strip("_")
    digest = hashlib.sha1(path.encode("utf-8")).hexdigest()[:10]
    return f"{stem}_{digest}"


def checkerboard(size: tuple[int, int], tile: int = 10) -> Image.Image:
    image = Image.new("RGB", size, (55, 55, 55))
    draw = ImageDraw.Draw(image)
    width, height = size
    for y in range(0, height, tile):
        for x in range(0, width, tile):
            color = (82, 82, 82) if ((x // tile) + (y // tile)) % 2 == 0 else (42, 42, 42)
            draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=color)
    return image


def make_thumbnail(src: Path, dest: Path) -> tuple[int, int]:
    with Image.open(src) as image:
        image = image.convert("RGBA")
        original_size = image.size
        image.thumbnail((THUMB_SIZE - 16, THUMB_SIZE - 16), Image.Resampling.LANCZOS)

        canvas = checkerboard((THUMB_SIZE, THUMB_SIZE))
        x = (THUMB_SIZE - image.width) // 2
        y = (THUMB_SIZE - image.height) // 2
        canvas.paste(image, (x, y), image)
        canvas.save(dest, "JPEG", quality=88, optimize=True)
        return original_size


def collect_blps(source: Path, limit: int) -> list[Path]:
    paths = sorted(source.rglob("*.blp"), key=lambda item: str(item).lower())
    upper_paths = sorted(source.rglob("*.BLP"), key=lambda item: str(item).lower())
    seen = {path.resolve() for path in paths}
    for path in upper_paths:
        resolved = path.resolve()
        if resolved not in seen:
            paths.append(path)
            seen.add(resolved)
    paths = sorted(paths, key=lambda item: str(item).lower())
    if limit > 0:
        return paths[:limit]
    return paths


def build_cards(items: list[dict[str, object]]) -> str:
    cards = []
    for item in items:
        path = html.escape(str(item["path"]))
        folder = html.escape(str(item["folder"]))
        image = html.escape(str(item["image"]))
        size = html.escape(str(item["size"]))
        search = html.escape(" ".join([str(item["path"]), str(item["folder"]), Path(str(item["path"])).name]).lower())
        cards.append(
            "\n".join(
                [
                    f'<article class="card" data-folder="{folder}" data-search="{search}">',
                    f'  <img src="{image}" alt="{path}" loading="lazy">',
                    f'  <div class="name">{html.escape(Path(path).name)}</div>',
                    f'  <div class="meta">{folder} / {size}</div>',
                    f"  <code>{path}</code>",
                    "</article>",
                ]
            )
        )
    return "\n".join(cards)


def build_folder_buttons(folders: list[str]) -> str:
    buttons = ['<button class="active" data-folder="All">All</button>']
    for folder in folders:
        escaped = html.escape(folder)
        buttons.append(f'<button data-folder="{escaped}">{escaped}</button>')
    return "\n".join(buttons)


def write_html(output: Path, items: list[dict[str, object]], failures: list[dict[str, str]]) -> None:
    folders = sorted({str(item["folder"]) for item in items}, key=str.lower)
    cards = build_cards(items)
    buttons = build_folder_buttons(folders)
    failures_json = html.escape(json.dumps(failures, indent=2))
    html_text = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>WotLK 3.3.5a Interface Texture Catalog</title>
<style>
body {{
  margin: 0;
  background: #15120e;
  color: #e8dcc4;
  font: 13px/1.4 Segoe UI, Arial, sans-serif;
}}
header {{
  position: sticky;
  top: 0;
  z-index: 2;
  padding: 14px 18px;
  background: #201a12;
  border-bottom: 1px solid #5a4626;
}}
h1 {{
  margin: 0 0 8px;
  color: #ffd36b;
  font-size: 20px;
  font-weight: 600;
}}
.toolbar {{
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}}
button {{
  border: 1px solid #6c542d;
  background: #2d2418;
  color: #e8dcc4;
  padding: 4px 8px;
  cursor: pointer;
}}
button.active {{
  border-color: #ffd36b;
  color: #ffd36b;
}}
.summary {{
  margin: 6px 0 0;
  color: #b9aa91;
}}
.search {{
  display: block;
  box-sizing: border-box;
  width: min(560px, 100%);
  margin: 8px 0 0;
  border: 1px solid #6c542d;
  background: #15120e;
  color: #e8dcc4;
  padding: 6px 8px;
  font: inherit;
}}
.search:focus {{
  border-color: #ffd36b;
  outline: none;
}}
.grid {{
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(214px, 1fr));
  gap: 10px;
  padding: 14px;
}}
.card {{
  min-height: 252px;
  border: 1px solid #41331d;
  background: #211b14;
  padding: 8px;
}}
.card img {{
  display: block;
  width: 160px;
  height: 160px;
  margin: 0 auto 8px;
  border: 1px solid #4c3b20;
  background: #333;
}}
.name {{
  color: #ffd36b;
  font-weight: 600;
  word-break: break-word;
}}
.meta {{
  color: #a99778;
  margin: 2px 0 6px;
}}
code {{
  display: block;
  color: #d6c7aa;
  white-space: normal;
  word-break: break-word;
}}
.hidden {{
  display: none;
}}
details {{
  margin-top: 8px;
}}
pre {{
  white-space: pre-wrap;
  color: #d6c7aa;
}}
</style>
</head>
<body>
<header>
  <h1>WotLK 3.3.5a Interface Texture Catalog</h1>
  <div class="toolbar">
{buttons}
  </div>
  <div class="summary">
    <span id="visibleCount">{len(items)}</span> / {len(items)} JPEG previews.
    Generated from local BLP files. Do not redistribute generated assets.
  </div>
  <input
    class="search"
    id="searchBox"
    type="search"
    placeholder="Search path, folder, or texture name"
    autocomplete="off">
  <details>
    <summary>Conversion failures: {len(failures)}</summary>
    <pre>{failures_json}</pre>
  </details>
</header>
<main class="grid" id="grid">
{cards}
</main>
<script>
const buttons = document.querySelectorAll("button[data-folder]");
const cards = document.querySelectorAll(".card");
const visibleCount = document.getElementById("visibleCount");
const searchBox = document.getElementById("searchBox");
let activeFolder = "All";
function applyFilters() {{
  const query = searchBox.value.trim().toLowerCase();
  let visible = 0;
  cards.forEach((card) => {{
    const folderMatch = activeFolder === "All" || card.dataset.folder === activeFolder;
    const searchMatch = query === "" || card.dataset.search.includes(query);
    const show = folderMatch && searchMatch;
    card.classList.toggle("hidden", !show);
    if (show) visible += 1;
  }});
  visibleCount.textContent = visible;
}}
buttons.forEach((button) => {{
  button.addEventListener("click", () => {{
    activeFolder = button.dataset.folder;
    buttons.forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    applyFilters();
  }});
}});
searchBox.addEventListener("input", applyFilters);
</script>
</body>
</html>
"""
    (output / "index.html").write_text(html_text, encoding="utf-8")


def build_catalog(source: Path, output: Path, limit: int) -> tuple[int, int]:
    thumbs = output / "thumbs"
    thumbs.mkdir(parents=True, exist_ok=True)

    items: list[dict[str, object]] = []
    failures: list[dict[str, str]] = []
    for src in collect_blps(source, limit):
        texture_path = rel_interface_path(src, source)
        folder = src.relative_to(source).parts[0]
        dest = thumbs / f"{safe_stem(texture_path)}.jpg"
        try:
            width, height = make_thumbnail(src, dest)
        except Exception as exc:  # noqa: BLE001 - catalog should continue on bad BLPs.
            failures.append({"path": str(src), "error": str(exc)})
            continue
        items.append(
            {
                "path": texture_path,
                "folder": folder,
                "image": "thumbs/" + dest.name,
                "size": f"{width}x{height}",
            }
        )

    write_html(output, items, failures)
    (output / "catalog.json").write_text(
        json.dumps({"items": items, "failures": failures}, indent=2),
        encoding="utf-8",
    )
    return len(items), len(failures)


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_dir():
        raise SystemExit(f"Interface source directory not found: {source}")

    converted, failed = build_catalog(source, output, args.limit)
    print(f"converted={converted}")
    print(f"failed={failed}")
    print(f"html={output / 'index.html'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
