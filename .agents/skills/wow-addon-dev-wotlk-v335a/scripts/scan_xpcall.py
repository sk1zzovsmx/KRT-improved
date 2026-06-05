#!/usr/bin/env python3
"""
scan_xpcall.py - Find variadic xpcall calls that silently break on WoW 3.3.5a.

Background:
    On Lua 5.2+: xpcall(fn, handler, arg1, arg2) forwards arg1, arg2 to fn.
    On Lua 5.1 (3.3.5a): trailing args are SILENTLY DROPPED. fn runs with no
    args and self=nil. No error fires; the addon "loads" but its widgets and
    callbacks fail in subtle ways.

    This is the #1 bug in Ace3-based addons (AceGUI v36+, AceConfig, etc.)
    when ported from Retail to a 3.3.5a private server.

Usage:
    python scan_xpcall.py <file_or_directory> [<file_or_directory> ...]

Exit codes:
    0 = no offenders found
    1 = at least one variadic xpcall found
    2 = invocation error

Approach:
    Tokenize-aware string/comment stripping (same as lint_lua51.py), then
    locate every `xpcall(...)` call site and parse its arguments at the
    top-level paren depth. If more than 2 top-level args appear, flag it.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Finding:
    file: Path
    line: int
    col: int
    args_found: int
    snippet: str

    def render(self) -> str:
        return (f"{self.file}:{self.line}:{self.col}: XPCALL-VARIADIC: "
                f"xpcall called with {self.args_found} args (Lua 5.1 supports only 2; "
                f"trailing args are silently dropped). "
                f"Replace with `pcall(fn, ...)` + manual error handler. "
                f"Snippet: {self.snippet}")


# ---------- Source preprocessor (shared style with lint_lua51.py) ----------

def _blank(span: str) -> str:
    return "".join("\n" if ch == "\n" else " " for ch in span)


def strip_strings_and_comments(src: str) -> str:
    """Blank out comments and strings so we don't false-positive on `xpcall(`
    appearing in a string literal or comment."""
    out: list[str] = []
    i = 0
    n = len(src)

    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        if ch == "-" and nxt == "-":
            j = i + 2
            if j < n and src[j] == "[":
                k = j + 1
                eq_count = 0
                while k < n and src[k] == "=":
                    eq_count += 1
                    k += 1
                if k < n and src[k] == "[":
                    closer = "]" + "=" * eq_count + "]"
                    end = src.find(closer, k + 1)
                    if end == -1:
                        end = n
                    else:
                        end += len(closer)
                    out.append(_blank(src[i:end]))
                    i = end
                    continue
            end = src.find("\n", i)
            if end == -1:
                end = n
            out.append(_blank(src[i:end]))
            i = end
            continue

        if ch == "[":
            k = i + 1
            eq_count = 0
            while k < n and src[k] == "=":
                eq_count += 1
                k += 1
            if k < n and src[k] == "[":
                closer = "]" + "=" * eq_count + "]"
                end = src.find(closer, k + 1)
                if end == -1:
                    end = n
                else:
                    end += len(closer)
                out.append(_blank(src[i:end]))
                i = end
                continue

        if ch in ('"', "'"):
            quote = ch
            j = i + 1
            while j < n:
                if src[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            out.append(_blank(src[i:j]))
            i = j
            continue

        out.append(ch)
        i += 1

    return "".join(out)


# ---------- xpcall scanner ----------

# Match `xpcall` followed by optional whitespace and `(`. Word-boundary on left
# to avoid matching `myxpcall` or `xxpcall`.
_XPCALL_RE = re.compile(r"\bxpcall\s*\(")


def find_matching_paren(src: str, open_pos: int) -> int:
    """Return the position of the `)` that matches the `(` at open_pos.
    Returns -1 if unmatched."""
    depth = 0
    i = open_pos
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def count_top_level_args(call_body: str) -> int:
    """Count comma-separated args at depth 0 within the parens.
    `call_body` is the text between (but not including) the outer parens.
    Tracks nesting for (), {}, []."""
    if not call_body.strip():
        return 0

    depth_paren = 0
    depth_brace = 0
    depth_bracket = 0
    args = 1   # at least one arg if call_body is non-empty

    for ch in call_body:
        if ch == "(":
            depth_paren += 1
        elif ch == ")":
            depth_paren -= 1
        elif ch == "{":
            depth_brace += 1
        elif ch == "}":
            depth_brace -= 1
        elif ch == "[":
            depth_bracket += 1
        elif ch == "]":
            depth_bracket -= 1
        elif (ch == "," and depth_paren == 0
              and depth_brace == 0 and depth_bracket == 0):
            args += 1

    return args


def _line_col(src: str, pos: int) -> tuple[int, int]:
    prefix = src[:pos]
    line = prefix.count("\n") + 1
    last_nl = prefix.rfind("\n")
    col = pos - last_nl if last_nl != -1 else pos + 1
    return line, col


def _snippet(src: str, start: int, end: int, max_len: int = 100) -> str:
    """One-line preview of the call site."""
    text = src[start:end].replace("\n", " ")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > max_len:
        text = text[: max_len - 3] + "..."
    return text


def scan_source(file: Path, src: str) -> list[Finding]:
    cleaned = strip_strings_and_comments(src)
    findings: list[Finding] = []

    for m in _XPCALL_RE.finditer(cleaned):
        # Position of the `(` is at m.end() - 1
        open_pos = m.end() - 1
        close_pos = find_matching_paren(cleaned, open_pos)
        if close_pos == -1:
            # Unmatched paren - likely a real bug, but not our concern
            continue

        body = cleaned[open_pos + 1 : close_pos]
        n_args = count_top_level_args(body)

        if n_args > 2:
            line, col = _line_col(cleaned, m.start())
            snippet = _snippet(src, m.start(), close_pos + 1)
            findings.append(Finding(file, line, col, n_args, snippet))

    findings.sort(key=lambda f: (str(f.file), f.line, f.col))
    return findings


# ---------- Walker / CLI ----------

def lua_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for p in paths:
        if p.is_file():
            if p.suffix.lower() == ".lua":
                files.append(p)
        elif p.is_dir():
            files.extend(sorted(p.rglob("*.lua")))
        else:
            print(f"warning: {p} is not a file or directory", file=sys.stderr)
    return files


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    paths = [Path(a) for a in argv[1:]]
    files = lua_files(paths)

    if not files:
        print("no .lua files found", file=sys.stderr)
        return 2

    total = 0
    for f in files:
        try:
            src = f.read_text(encoding="utf-8", errors="replace")
        except OSError as e:
            print(f"error reading {f}: {e}", file=sys.stderr)
            continue
        for finding in scan_source(f, src):
            print(finding.render())
            total += 1

    if total == 0:
        print(f"OK: {len(files)} file(s) clean of variadic xpcall",
              file=sys.stderr)
        return 0
    print(f"\n{total} variadic xpcall call(s) in {len(files)} file(s)",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
