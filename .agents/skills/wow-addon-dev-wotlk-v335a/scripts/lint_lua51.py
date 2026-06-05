#!/usr/bin/env python3
"""
lint_lua51.py - Detect Lua 5.2+ syntax features that won't parse on WoW 3.3.5a.

The 3.3.5a client embeds Lua 5.1.5. This script greps for syntax constructs
that were added in Lua 5.2 or later and will produce parse errors at addon
load time.

Usage:
    python lint_lua51.py <file_or_directory> [<file_or_directory> ...]

Exit codes:
    0 = no issues found
    1 = at least one issue found
    2 = invocation error (bad path, etc.)

Detected issues:
    LUA52-GOTO    - `goto label` statement (Lua 5.2+)
    LUA52-LABEL   - `::label::` syntax (Lua 5.2+)
    LUA53-IDIV    - `//` integer division (Lua 5.3+)
    LUA53-BITAND  - `&` bitwise AND (Lua 5.3+)
    LUA53-BITOR   - `|` bitwise OR (Lua 5.3+)
    LUA53-BITNOT  - `~` as unary bitwise NOT (Lua 5.3+) - NOT the binary `~=` operator
    LUA53-LSHIFT  - `<<` left shift (Lua 5.3+)
    LUA53-RSHIFT  - `>>` right shift (Lua 5.3+)
    LUA52-ZESC    - `\\z` whitespace-skipping string escape (Lua 5.2+)
    LUA52-ENV     - `_ENV` upvalue reference (Lua 5.2+); use setfenv/getfenv on 5.1
    LUA52-PACK    - `table.pack(...)` (Lua 5.2+); use {n=select("#", ...), ...}
    LUA52-UNPACK  - `table.unpack(...)` (Lua 5.2+); use global `unpack` on 5.1
    LUA52-BIT32   - `bit32.*` namespace (Lua 5.2+); use the global `bit.*` namespace

Approach:
    Lua source is preprocessed to blank out comments and string literals
    (replacing them with same-length spaces, preserving line/column numbers),
    then regex matches are run on the cleaned source. This avoids
    false positives from `//` appearing in a string or `&` in a comment.
    Edge cases involving deeply nested long-bracket strings may be missed.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


# ---------- Issue model ----------

@dataclass(frozen=True)
class Issue:
    file: Path
    line: int
    col: int
    code: str
    message: str

    def render(self) -> str:
        return f"{self.file}:{self.line}:{self.col}: {self.code}: {self.message}"


# ---------- Source preprocessor ----------
# Blank out comments and string literals so regex-based scanning of code
# tokens doesn't false-positive on string contents or comments.

def _blank(span: str) -> str:
    """Replace span with same-length whitespace, preserving newlines."""
    return "".join("\n" if ch == "\n" else " " for ch in span)


def strip_strings_and_comments(src: str) -> tuple[str, list[tuple[int, int]]]:
    """
    Walk the source character by character, blanking out:
      - line comments      -- ... \n
      - block comments     --[[ ... ]] / --[=[ ... ]=]
      - short strings      "..."  '...'   (with backslash escapes)
      - long strings       [[ ... ]] / [=[ ... ]=]

    Newlines are preserved so that line/column numbers in matches against
    the cleaned source still correspond to the original file.

    Returns (cleaned_source, short_string_spans) where short_string_spans
    is a list of (start, end) char offsets into the ORIGINAL source for
    each short-string literal. Used by the \\z detector, which needs to
    inspect string contents (the cleaned source has them blanked).
    """
    out: list[str] = []
    short_string_spans: list[tuple[int, int]] = []
    i = 0
    n = len(src)

    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        # Comment: -- ...
        if ch == "-" and nxt == "-":
            # Check for block comment: --[=*[
            j = i + 2
            if j < n and src[j] == "[":
                # Count equals signs
                k = j + 1
                eq_count = 0
                while k < n and src[k] == "=":
                    eq_count += 1
                    k += 1
                if k < n and src[k] == "[":
                    # Block comment opener: --[<eq>[
                    closer = "]" + "=" * eq_count + "]"
                    end = src.find(closer, k + 1)
                    if end == -1:
                        # Unterminated - treat rest of file as comment
                        end = n
                    else:
                        end += len(closer)
                    out.append(_blank(src[i:end]))
                    i = end
                    continue
            # Line comment: blank to next newline
            end = src.find("\n", i)
            if end == -1:
                end = n
            out.append(_blank(src[i:end]))
            i = end
            continue

        # Long string: [=*[ ... ]=*]
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
                # Long strings cannot contain \z (no escape processing in [[..]]),
                # so don't record them for the \z scanner.
                out.append(_blank(src[i:end]))
                i = end
                continue

        # Short string
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
                    # Unterminated short string - bail
                    break
                j += 1
            short_string_spans.append((i, j))
            out.append(_blank(src[i:j]))
            i = j
            continue

        out.append(ch)
        i += 1

    return "".join(out), short_string_spans


# ---------- Detectors ----------
# Each detector takes the cleaned source and yields (line, col, code, msg).
# Patterns operate on cleaned source (strings/comments already blanked).

# Order matters for ~=  vs  ~ : we detect ~= first and skip those positions.

_PATTERNS: list[tuple[str, str, str]] = [
    # (regex, code, message)
    (r"\bgoto\s+\w+\b", "LUA52-GOTO",
     "`goto` is a Lua 5.2+ statement; refactor with if/break/return"),
    (r"::\s*\w+\s*::", "LUA52-LABEL",
     "`::label::` is Lua 5.2+ syntax"),
    (r"//", "LUA53-IDIV",
     "`//` integer division is Lua 5.3+; use math.floor(a / b)"),
    (r"<<", "LUA53-LSHIFT",
     "`<<` is Lua 5.3+; use bit.lshift(value, n)"),
    (r">>", "LUA53-RSHIFT",
     "`>>` is Lua 5.3+; use bit.rshift(value, n)"),
    (r"\b_ENV\b", "LUA52-ENV",
     "`_ENV` is Lua 5.2+; use setfenv()/getfenv() on Lua 5.1"),
    (r"\btable\.pack\s*\(", "LUA52-PACK",
     "`table.pack` is Lua 5.2+; use {n=select('#', ...), ...}"),
    (r"\btable\.unpack\s*\(", "LUA52-UNPACK",
     "`table.unpack` is Lua 5.2+; use the global `unpack` on Lua 5.1"),
    (r"\bbit32\.", "LUA52-BIT32",
     "`bit32` is Lua 5.2+; the WoW 3.3.5 client provides the global `bit.*` namespace"),
]

# Bitwise & and | need special handling because they don't appear in normal
# Lua 5.1 syntax at all - so any occurrence is suspicious. But we want to
# be careful: an isolated & or | is rare, and we want to point at the operator.
# We match them as standalone tokens (not part of && / || which are JS-isms
# users sometimes mistype, but those would also be syntax errors).

_BITAND_RE = re.compile(r"(?<![&|])&(?![&|=])")
_BITOR_RE = re.compile(r"(?<![&|])\|(?![&|=])")

# Bitwise ~ (unary) vs ~= (not-equal): we need to find ~ that is NOT followed
# by = and NOT preceded by anything that makes it not-equal context.
# In Lua 5.1, ~ is ONLY valid as part of ~=. A bare ~ followed by anything
# other than = is either a Lua 5.3 bitwise NOT (invalid on 5.1) or a syntax
# error anyway. We flag ~ that is not part of ~=.
_BITNOT_RE = re.compile(r"~(?!=)")


def _line_col(src: str, pos: int) -> tuple[int, int]:
    """Convert a character offset into 1-indexed (line, column)."""
    prefix = src[:pos]
    line = prefix.count("\n") + 1
    last_nl = prefix.rfind("\n")
    col = pos - last_nl if last_nl != -1 else pos + 1
    return line, col


def lint_source(file: Path, src: str) -> list[Issue]:
    cleaned, short_string_spans = strip_strings_and_comments(src)
    issues: list[Issue] = []

    for pattern, code, msg in _PATTERNS:
        for m in re.finditer(pattern, cleaned):
            line, col = _line_col(cleaned, m.start())
            issues.append(Issue(file, line, col, code, msg))

    for m in _BITAND_RE.finditer(cleaned):
        line, col = _line_col(cleaned, m.start())
        issues.append(Issue(
            file, line, col, "LUA53-BITAND",
            "`&` bitwise AND is Lua 5.3+; use bit.band(a, b)"))

    for m in _BITOR_RE.finditer(cleaned):
        line, col = _line_col(cleaned, m.start())
        issues.append(Issue(
            file, line, col, "LUA53-BITOR",
            "`|` bitwise OR is Lua 5.3+; use bit.bor(a, b)"))

    for m in _BITNOT_RE.finditer(cleaned):
        line, col = _line_col(cleaned, m.start())
        issues.append(Issue(
            file, line, col, "LUA53-BITNOT",
            "`~` as unary bitwise NOT is Lua 5.3+; use bit.bnot(value). "
            "(`~=` is fine - this match is NOT followed by `=`.)"))

    # \z escape: only valid inside short strings (long strings don't process
    # escape sequences). Scan string contents in the original source.
    zesc_re = re.compile(r"\\z")
    for s_start, s_end in short_string_spans:
        for m in zesc_re.finditer(src, s_start, s_end):
            line, col = _line_col(src, m.start())
            issues.append(Issue(
                file, line, col, "LUA52-ZESC",
                "`\\z` string escape is Lua 5.2+; concatenate string fragments instead"))

    issues.sort(key=lambda i: (str(i.file), i.line, i.col))
    return issues


# ---------- Walker ----------

def lua_files(paths: list[Path]) -> list[Path]:
    """Expand directory paths to all .lua files within them."""
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


# ---------- CLI ----------

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
        for issue in lint_source(f, src):
            print(issue.render())
            total += 1

    if total == 0:
        print(f"OK: {len(files)} file(s) clean", file=sys.stderr)
        return 0
    print(f"\n{total} issue(s) in {len(files)} file(s)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
