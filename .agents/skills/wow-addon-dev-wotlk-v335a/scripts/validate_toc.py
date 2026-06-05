#!/usr/bin/env python3
"""
validate_toc.py - Validate WoW addon .toc files for the 3.3.5a (Interface 30300) client.

Checks:
    1. Required directives present: Interface, Title
    2. Interface version is exactly 30300 (warns on other valid client versions)
    3. SavedVariables identifiers are well-formed (comma-separated, valid Lua names)
    4. No 5.2+/Retail-only TOC directives (AllowLoadGameType, DefaultState,
       SecureHandlerVersion, LoadManagers, RequiredDeps)
    5. Listed files exist on disk relative to the TOC
    6. No mixed path separators (warns)

Usage:
    python validate_toc.py <path/to/Addon.toc> [<path2.toc> ...]

Exit codes:
    0 = no errors (warnings allowed)
    1 = at least one error
    2 = invocation error
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Known WoW Interface versions (for friendly warnings)
KNOWN_INTERFACES = {
    "11200": "Vanilla 1.12",
    "20400": "TBC 2.4.3",
    "30300": "WotLK 3.3.5 (TARGET)",
    "30400": "WotLK 3.4.x (Classic re-release)",
    "40300": "Cataclysm 4.3.4",
    "50400": "MoP 5.4.8",
    "60200": "WoD 6.2.4",
    "70300": "Legion 7.3.5",
    "80100": "BfA 8.1",
    "90100": "Shadowlands 9.1",
    "100000": "Dragonflight 10.0",
    "110000": "TWW 11.0",
}

# Directives that exist on retail but not on 3.3.5
FORBIDDEN_DIRECTIVES = {
    "AllowLoadGameType": "retail-only; addon will silently fail to load on 3.3.5",
    "DefaultState": "not honored on 3.3.5",
    "SecureHandlerVersion": "not parsed on 3.3.5",
    "LoadManagers": "not honored on 3.3.5",
    "RequiredDeps": "use `## Dependencies:` instead (no version specifiers)",
}

# Recognized 3.3.5 directives - anything outside this set gets a warning
KNOWN_DIRECTIVES = {
    "Interface", "Title", "Notes", "Author", "Version",
    "SavedVariables", "SavedVariablesPerCharacter",
    "Dependencies", "OptionalDeps",
    "LoadOnDemand", "LoadWith", "LoadManagers",
    # Localized variants
} | {f"Title-{lang}" for lang in (
    "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR",
    "ruRU", "zhCN", "zhTW")} | {f"Notes-{lang}" for lang in (
    "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR",
    "ruRU", "zhCN", "zhTW")}

LUA_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


@dataclass(frozen=True)
class Finding:
    file: Path
    line: int
    severity: str  # "error" | "warning"
    code: str
    message: str

    def render(self) -> str:
        return f"{self.file}:{self.line}: {self.severity}: {self.code}: {self.message}"


def parse_toc(path: Path) -> tuple[dict[str, tuple[int, str]], list[tuple[int, str]], list[Finding]]:
    """Parse a TOC file. Returns (directives, file_lines, parse_errors).

    directives maps Directive name -> (line_number, value).
    file_lines is a list of (line_number, file_path_string).
    parse_errors is a list of malformed-line findings.
    """
    directives: dict[str, tuple[int, str]] = {}
    files: list[tuple[int, str]] = []
    errors: list[Finding] = []

    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
    except OSError as e:
        return {}, [], [Finding(path, 0, "error", "TOC-IO",
                                f"cannot read file: {e}")]

    for ln, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        stripped = line.strip()

        if not stripped:
            continue

        # Comment line: # ... (TOC uses # for comments, not --)
        # Directive line: ## Name: value
        if stripped.startswith("##"):
            body = stripped[2:].strip()
            if ":" not in body:
                errors.append(Finding(path, ln, "error", "TOC-SYNTAX",
                                      f"directive missing colon: {stripped!r}"))
                continue
            name, _, value = body.partition(":")
            name = name.strip()
            value = value.strip()
            if name in directives:
                errors.append(Finding(path, ln, "warning", "TOC-DUPDIRECTIVE",
                                      f"directive `{name}` redefined; "
                                      f"first occurrence on line {directives[name][0]}"))
            directives[name] = (ln, value)
            continue

        if stripped.startswith("#"):
            # Comment, skip
            continue

        # File line
        files.append((ln, stripped))

    return directives, files, errors


def validate(path: Path) -> list[Finding]:
    findings: list[Finding] = []
    directives, files, parse_errors = parse_toc(path)
    findings.extend(parse_errors)

    # 1. Interface
    iface = directives.get("Interface")
    if iface is None:
        findings.append(Finding(path, 0, "error", "TOC-NOIFACE",
                                "missing required `## Interface:` directive"))
    else:
        ln, val = iface
        if val != "30300":
            label = KNOWN_INTERFACES.get(val, "unknown client version")
            severity = "warning" if val in KNOWN_INTERFACES else "error"
            findings.append(Finding(path, ln, severity, "TOC-IFACE",
                                    f"Interface is `{val}` ({label}); "
                                    f"this skill targets 30300 (WotLK 3.3.5a)"))

    # 2. Title
    title = directives.get("Title")
    if title is None:
        findings.append(Finding(path, 0, "warning", "TOC-NOTITLE",
                                "missing `## Title:` - addon will display its folder name"))
    elif not title[1].strip():
        findings.append(Finding(path, title[0], "warning", "TOC-EMPTYTITLE",
                                "`## Title:` is empty - addon will display its folder name"))

    # 3. SavedVariables format
    for sv_directive in ("SavedVariables", "SavedVariablesPerCharacter"):
        sv = directives.get(sv_directive)
        if sv is None:
            continue
        ln, val = sv
        if not val:
            findings.append(Finding(path, ln, "error", "TOC-EMPTYSV",
                                    f"`{sv_directive}` is empty"))
            continue
        for ident in (s.strip() for s in val.split(",")):
            if not ident:
                findings.append(Finding(path, ln, "error", "TOC-SVNAME",
                                        f"empty identifier in `{sv_directive}`"))
                continue
            if not LUA_IDENT_RE.match(ident):
                findings.append(Finding(path, ln, "error", "TOC-SVNAME",
                                        f"invalid Lua identifier in `{sv_directive}`: {ident!r}"))

    # 4. Forbidden directives
    for d, reason in FORBIDDEN_DIRECTIVES.items():
        if d in directives:
            ln = directives[d][0]
            findings.append(Finding(path, ln, "error", "TOC-FORBIDDEN",
                                    f"directive `{d}` is forbidden: {reason}"))

    # 5. Unknown directives (lower priority - warn)
    for name, (ln, _) in directives.items():
        if name in FORBIDDEN_DIRECTIVES:
            continue  # already reported as error
        if name in KNOWN_DIRECTIVES:
            continue
        if name.startswith("X-"):
            # X-Curse-*, X-Wago-*, etc. - informational metadata, harmless
            continue
        findings.append(Finding(path, ln, "warning", "TOC-UNKNOWNDIRECTIVE",
                                f"unrecognized directive `{name}` (ignored by 3.3.5 client)"))

    # 6. File existence and path separators
    base = path.parent
    for ln, file_path in files:
        # Mixed separators warning
        if "/" in file_path and "\\" in file_path:
            findings.append(Finding(path, ln, "warning", "TOC-MIXEDSEP",
                                    f"mixed path separators in {file_path!r}"))
        # Normalize for filesystem check
        normalized = file_path.replace("\\", "/")
        target = (base / normalized)
        if not target.exists():
            findings.append(Finding(path, ln, "error", "TOC-NOFILE",
                                    f"listed file does not exist: {file_path}"))

    # 7. LoadOnDemand without LoadWith warning (informational)
    lod = directives.get("LoadOnDemand")
    if lod and lod[1] in ("1", "true", "True") and "LoadWith" not in directives:
        findings.append(Finding(path, lod[0], "warning", "TOC-LODNOLOADWITH",
                                "LoadOnDemand is enabled but no LoadWith directive; "
                                "addon must be loaded via LoadAddOn() programmatically"))

    return findings


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    paths = [Path(a) for a in argv[1:]]
    error_total = 0
    warning_total = 0

    for p in paths:
        if not p.exists():
            print(f"{p}: error: file not found", file=sys.stderr)
            error_total += 1
            continue
        if p.suffix.lower() != ".toc":
            print(f"{p}: warning: not a .toc file, skipping", file=sys.stderr)
            continue

        findings = validate(p)
        for f in findings:
            print(f.render())
            if f.severity == "error":
                error_total += 1
            else:
                warning_total += 1

    summary = f"\n{error_total} error(s), {warning_total} warning(s) in {len(paths)} file(s)"
    if error_total == 0:
        print(f"OK: {summary.strip()}", file=sys.stderr)
        return 0
    print(summary, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
