#!/usr/bin/env python3
"""Cross-platform entrypoint for the most common KRT repo tooling."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any


MECHANIC_ACTIONS = (
    "EnvStatus",
    "ToolsStatus",
    "AddonValidate",
    "DocsStale",
    "AddonDeadcode",
    "AddonLint",
    "AddonFormat",
    "AddonSecurity",
    "AddonComplexity",
    "AddonDeprecations",
    "AddonOutput",
)

MECHANIC_COMMANDS = {
    "EnvStatus": "env.status",
    "ToolsStatus": "tools.status",
    "AddonValidate": "addon.validate",
    "DocsStale": "docs.stale",
    "AddonDeadcode": "addon.deadcode",
    "AddonLint": "addon.lint",
    "AddonFormat": "addon.format",
    "AddonSecurity": "addon.security",
    "AddonComplexity": "addon.complexity",
    "AddonDeprecations": "addon.deprecations",
    "AddonOutput": "addon.output",
}


class CliError(Exception):
    """Raised for user-facing CLI errors."""


def is_windows() -> bool:
    return os.name == "nt"


def repo_root_from(start: Path) -> Path:
    current = start.resolve()
    while True:
        if (current / "!KRT" / "!KRT.toc").is_file():
            return current
        if current.parent == current:
            raise CliError(f"Unable to resolve repo root from '{start}'.")
        current = current.parent


REPO_ROOT = repo_root_from(Path(__file__).resolve().parent)
TOOLS_DIR = REPO_ROOT / "tools"
ADDON_DIR = REPO_ROOT / "!KRT"
TOC_PATH = ADDON_DIR / "!KRT.toc"
ADDON_CHANGELOG_PATH = ADDON_DIR / "CHANGELOG.md"

REPO_CHECK_SCRIPTS = {
    "api_nomenclature": "check-api-nomenclature.ps1",
    "layering": "check-layering.ps1",
    "lua_syntax": "check-lua-syntax.ps1",
    "lua_uniformity": "check-lua-uniformity.ps1",
    "raid_hardening": "check-raid-hardening.ps1",
    "toc_files": "check-toc-files.ps1",
    "ui_binding": "check-ui-binding.ps1",
}


def first_command(candidates: list[str]) -> str | None:
    for candidate in candidates:
        if not candidate:
            continue
        found = shutil.which(candidate)
        if found:
            return found
    return None


def powershell_executable() -> str | None:
    override = os.environ.get("KRT_POWERSHELL_EXE", "").strip()
    if override:
        if Path(override).is_file():
            return str(Path(override).resolve())
        found = shutil.which(override)
        if found:
            return found
        return None

    return first_command(["pwsh", "pwsh.exe", "powershell", "powershell.exe"])


def powershell_script_arg(script_path: Path, powershell: str) -> str:
    script_arg = str(script_path)
    if is_windows():
        return script_arg

    command_name = Path(powershell).name.lower()
    is_windows_host = command_name.endswith(".exe") or command_name == "powershell"
    if not is_windows_host:
        return script_arg

    for converter in ("wslpath", "cygpath"):
        converter_path = shutil.which(converter)
        if not converter_path:
            continue
        converted = run_command_capture([converter_path, "-w", script_arg], cwd=REPO_ROOT)
        if converted.returncode == 0:
            value = converted.stdout.strip()
            if value:
                return value

    return script_arg


def default_mechanic_root() -> Path:
    override = os.environ.get("KRT_MECHANIC_ROOT", "").strip()
    if override:
        return Path(override).expanduser()
    if is_windows():
        return Path("C:/dev/Mechanic")
    return Path.home() / "dev" / "Mechanic"


def default_mechanic_executable() -> str | None:
    override = os.environ.get("KRT_MECHANIC_EXE", "").strip()
    if override:
        return override

    mechanic_root = default_mechanic_root()
    if is_windows():
        candidate = mechanic_root / "desktop" / ".venv" / "Scripts" / "mech.exe"
    else:
        candidate = mechanic_root / "desktop" / ".venv" / "bin" / "mech"

    if candidate.is_file():
        return str(candidate.resolve())

    return first_command(["mech"])


def local_skills_root() -> Path:
    override = os.environ.get("KRT_LOCAL_SKILLS_ROOT", "").strip()
    if override:
        return Path(override).expanduser()
    return Path.home() / ".codex" / "skills"


def run_command(command: list[str], *, cwd: Path | None = None) -> int:
    completed = subprocess.run(command, cwd=str(cwd or REPO_ROOT), check=False)
    return completed.returncode


def run_command_capture(command: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd or REPO_ROOT),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def run_powershell_script(script_name: str, args: list[str] | None = None) -> int:
    powershell = powershell_executable()
    if not powershell:
        raise CliError("PowerShell not found. Set KRT_POWERSHELL_EXE or install PowerShell.")

    script_path = TOOLS_DIR / script_name
    if not script_path.is_file():
        raise CliError(f"PowerShell script not found: {script_path}")
    script_arg = powershell_script_arg(script_path, powershell)

    command = [
        powershell,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_arg,
    ]
    if args:
        command.extend(args)
    return run_command(command, cwd=REPO_ROOT)


def read_toc_version() -> str:
    if not TOC_PATH.is_file():
        raise CliError(f"TOC file not found: {TOC_PATH}")

    for line in TOC_PATH.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("## Version:"):
            value = line.split(":", 1)[1].strip()
            if value:
                return value

    return "dev"


def extract_release_version_from_text(
    text: str,
    *,
    require_unreleased_release_version: bool,
    source_label: str,
) -> str | None:
    lines = text.splitlines()
    in_unreleased = False
    collected: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if line.strip() == "## Unreleased":
                in_unreleased = True
                continue
            if in_unreleased:
                break
        if in_unreleased:
            collected.append(line)

    for line in collected:
        stripped = line.strip()
        if stripped.startswith("Release-Version:"):
            value = stripped.split(":", 1)[1].strip()
            if value:
                return value
            raise CliError(f"{source_label} contains an empty 'Release-Version:' entry.")

    if require_unreleased_release_version:
        if not collected:
            raise CliError(f"{source_label} is missing the '## Unreleased' section.")
        raise CliError(f"{source_label} must declare 'Release-Version: <version>' under '## Unreleased'.")

    release_heading = re.search(r"^## \[([^\]]+)\]", text, flags=re.MULTILINE)
    if release_heading:
        return release_heading.group(1).strip()

    return None


def read_addon_changelog_release_version() -> str:
    if not ADDON_CHANGELOG_PATH.is_file():
        raise CliError(f"Addon changelog not found: {ADDON_CHANGELOG_PATH}")

    text = ADDON_CHANGELOG_PATH.read_text(encoding="utf-8", errors="replace")
    version = extract_release_version_from_text(
        text,
        require_unreleased_release_version=True,
        source_label=str(ADDON_CHANGELOG_PATH),
    )
    assert version is not None
    return version


def parse_release_version(version: str) -> tuple[str, str]:
    match = re.fullmatch(r"(\d+\.\d+\.\d+)([A-Za-z])", version.strip())
    if not match:
        raise CliError(
            f"Release version '{version}' must use the format x.x.xA, x.x.xB, or x.x.xR."
        )
    return match.group(1), match.group(2).upper()


def resolve_release_channel(version: str) -> tuple[str, bool]:
    _, suffix = parse_release_version(version)
    mapping = {
        "A": ("alpha", True),
        "B": ("beta", True),
        "R": ("release", False),
    }
    if suffix not in mapping:
        raise CliError(
            f"Release version '{version}' must end with A, B, or R to resolve alpha, beta, or release."
        )

    return mapping[suffix]


def resolve_release_metadata(expected_channel: str | None = None) -> dict[str, Any]:
    changelog_version = read_addon_changelog_release_version()
    addon_version = read_toc_version()
    if changelog_version.lower() != addon_version.lower():
        raise CliError(
            "!KRT/CHANGELOG.md Release-Version does not match !KRT/!KRT.toc version: "
            f"'{changelog_version}' vs '{addon_version}'."
        )

    version_core, version_suffix = parse_release_version(changelog_version)
    channel, prerelease = resolve_release_channel(changelog_version)
    if expected_channel and channel != expected_channel:
        raise CliError(
            f"Expected release channel '{expected_channel}', but changelog version '{changelog_version}' "
            f"resolves to '{channel}'."
        )

    tag = f"{channel}-{changelog_version}"
    publishable = channel != "alpha"
    return {
        "version": changelog_version,
        "version_core": version_core,
        "version_suffix": version_suffix,
        "addon_version": addon_version,
        "channel": channel,
        "prerelease": prerelease,
        "publishable": publishable,
        "tag": tag,
        "asset_name": f"KRT-{tag}.zip",
        "checksum_name": f"KRT-{tag}.zip.sha256",
        "release_title": tag,
    }


def write_github_output(path_text: str, payload: dict[str, Any]) -> None:
    output_path = Path(path_text)
    with output_path.open("a", encoding="utf-8") as handle:
        for key, value in payload.items():
            if isinstance(value, bool):
                rendered = "true" if value else "false"
            else:
                rendered = str(value)
            handle.write(f"{key}={rendered}\n")


def safe_version_text(value: str) -> str:
    unsafe = '\\/:*?"<>| '
    safe = "".join("-" if ch in unsafe else ch for ch in value)
    return safe or "dev"


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def build_release_zip(args: argparse.Namespace) -> int:
    if not ADDON_DIR.is_dir():
        raise CliError(f"Addon folder not found: {ADDON_DIR}")

    version = args.version.strip() if args.version else read_toc_version()
    file_name = args.file_name or f"KRT-{safe_version_text(version)}.zip"

    output_dir = Path(args.output_dir).expanduser()
    if not output_dir.is_absolute():
        output_dir = (REPO_ROOT / output_dir).resolve()
    ensure_dir(output_dir)

    zip_path = output_dir / file_name
    if zip_path.exists():
        zip_path.unlink()

    print(f"Building release archive: {zip_path}")
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file_path in sorted(ADDON_DIR.rglob("*")):
            if file_path.is_file():
                archive.write(file_path, file_path.relative_to(REPO_ROOT).as_posix())

    with zipfile.ZipFile(zip_path, "r") as archive:
        unexpected = [
            name for name in archive.namelist()
            if name.strip() and name != "!KRT/" and not name.startswith("!KRT/")
        ]
    if unexpected:
        sample = ", ".join(unexpected[:5])
        raise CliError(f"Archive validation failed. Unexpected entries: {sample}")

    print(f"Archive ready: {zip_path}")
    print("Contents root: !KRT/")

    if args.write_checksum:
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        checksum_path = Path(f"{zip_path}.sha256")
        checksum_path.write_text(f"{digest}  {zip_path.name}", encoding="utf-8")
        print(f"Checksum ready: {checksum_path}")

    return 0


def install_hooks(_: argparse.Namespace) -> int:
    git = first_command(["git"])
    if not git:
        raise CliError("git not found in PATH.")

    command = [git, "config", "core.hooksPath", ".githooks"]
    result = run_command(command, cwd=REPO_ROOT)
    if result != 0:
        raise CliError("git config core.hooksPath .githooks failed.")

    print("Configured core.hooksPath=.githooks")
    return 0


def repo_quality_check(args: argparse.Namespace) -> int:
    script_name = REPO_CHECK_SCRIPTS[args.check]
    print(f"Running check '{args.check}' via {script_name}...", flush=True)
    return run_powershell_script(script_name, [])


def skills_manifest(args: argparse.Namespace) -> int:
    manifest_path = TOOLS_DIR / "agent-skills.manifest.json"
    if not manifest_path.is_file():
        raise CliError(f"Skills manifest not found: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if args.json:
        print(json.dumps(manifest, indent=2))
        return 0

    sources = manifest.get("sources", [])
    print(f"Manifest: {manifest_path}")
    print(f"Version: {manifest.get('version')}")
    print("")
    print("Skills:")
    for source in sources:
        skill = str(source.get("skill", "")).strip() or "<unknown>"
        repo = str(source.get("repo", "")).strip() or "<repo?>"
        commit = str(source.get("commit", "")).strip() or "<commit?>"
        destination = str(source.get("destinationPath", "")).strip()
        suffix = f" -> {destination}" if destination else ""
        print(f"  - {skill}: {repo}@{commit}{suffix}")
    return 0


def skills_sync(args: argparse.Namespace) -> int:
    if args.verify_only and args.install_local:
        raise CliError("Use either --verify-only or --install-local, not both.")

    ps_args: list[str] = []
    if args.verify_only:
        ps_args.append("-VerifyOnly")
    if args.install_local:
        ps_args.append("-InstallLocal")
    if args.local_skills_root:
        root = str(Path(args.local_skills_root).expanduser())
        ps_args.extend(["-LocalSkillsRoot", root])
    return run_powershell_script("sync-agent-skills.ps1", ps_args)


def mechanic_bootstrap(args: argparse.Namespace) -> int:
    ps_args: list[str] = []
    if args.mechanic_root:
        root = str(Path(args.mechanic_root).expanduser())
        ps_args.extend(["-MechanicRoot", root])
    if args.repo_url:
        ps_args.extend(["-RepoUrl", args.repo_url])
    if args.ref:
        ps_args.extend(["-Ref", args.ref])
    if args.pull:
        ps_args.append("-Pull")
    if args.skip_pip_upgrade:
        ps_args.append("-SkipPipUpgrade")
    if args.run_setup_tools:
        ps_args.append("-RunSetupTools")
    return run_powershell_script("mech-bootstrap.ps1", ps_args)


def run_krt_mcp(args: argparse.Namespace) -> int:
    server_path = TOOLS_DIR / "krt_mcp_server.py"
    if not server_path.is_file():
        raise CliError(f"MCP server not found: {server_path}")

    python_exe = args.python_exe or sys.executable
    if not python_exe:
        raise CliError("Python executable not found.")

    return run_command([python_exe, str(server_path)], cwd=REPO_ROOT)


def mechanic_payload(args: argparse.Namespace) -> dict[str, Any]:
    payload: dict[str, Any]
    if args.action in ("EnvStatus", "ToolsStatus"):
        payload = {}
    elif args.action == "AddonOutput":
        payload = {"agent_mode": bool(args.agent_mode)}
    else:
        addon_path = Path(args.addon_path).expanduser() if args.addon_path else ADDON_DIR
        addon_path = addon_path.resolve()
        if not addon_path.is_dir():
            raise CliError(f"Addon path does not exist: {addon_path}")

        payload = {
            "addon": args.addon_name,
            "path": str(addon_path),
        }

        if args.action in ("AddonDeadcode", "AddonSecurity", "DocsStale"):
            payload["include_suspicious"] = bool(args.include_suspicious)
        if args.action == "AddonFormat":
            payload["check"] = bool(args.format_check)
        if args.action in ("AddonDeadcode", "AddonSecurity", "AddonComplexity") and args.categories:
            payload["categories"] = args.categories
        if args.action == "AddonDeprecations":
            payload["min_severity"] = args.min_severity

    return payload


def mechanic(args: argparse.Namespace) -> int:
    if args.json and args.agent_mode:
        raise CliError("Use either --json or --agent-mode, not both.")
    if args.action != "AddonOutput" and args.agent_mode:
        raise CliError("--agent-mode is only valid with action AddonOutput.")

    mechanic_exe = args.mechanic_exe or default_mechanic_executable()
    if not mechanic_exe:
        raise CliError(
            "Mechanic executable not found. Set KRT_MECHANIC_EXE or install Mechanic on this machine."
        )

    mech_path = Path(mechanic_exe).expanduser()
    if mech_path.is_file():
        command = [str(mech_path.resolve())]
    else:
        found = shutil.which(mechanic_exe)
        if not found:
            raise CliError(f"Mechanic executable not found: {mechanic_exe}")
        command = [found]

    if args.json:
        command.append("--json")
    elif args.agent_mode:
        command.append("--agent")

    command.extend(["call", MECHANIC_COMMANDS[args.action]])
    payload = mechanic_payload(args)
    if payload:
        command.append(json.dumps(payload, separators=(",", ":")))

    return run_command(command, cwd=REPO_ROOT)


def command_status(name: str, candidates: list[str], required: bool, purpose: str) -> dict[str, Any]:
    resolved = first_command(candidates)
    status = "ready" if resolved else ("missing" if required else "warning")
    return {
        "name": name,
        "required": required,
        "purpose": purpose,
        "requested": candidates,
        "available": bool(resolved),
        "status": status,
        "path": resolved,
    }


def path_status(name: str, path: Path, required: bool, *, directory: bool = False) -> dict[str, Any]:
    exists = path.is_dir() if directory else path.is_file()
    status = "ready" if exists else ("missing" if required else "warning")
    return {
        "name": name,
        "required": required,
        "path": str(path),
        "exists": exists,
        "status": status,
    }


def load_manifest() -> tuple[dict[str, Any] | None, str | None]:
    manifest_path = TOOLS_DIR / "agent-skills.manifest.json"
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8")), None
    except Exception as exc:  # pragma: no cover - defensive surface
        return None, str(exc)


def verify_skills_if_requested(verify_skills: bool) -> dict[str, Any] | None:
    if not verify_skills:
        return None

    powershell = powershell_executable()
    if not powershell:
        return {
            "ok": False,
            "status": "unavailable",
            "reason": "PowerShell is required for skills verification.",
        }

    result = run_command_capture(
        [
            powershell,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            powershell_script_arg(TOOLS_DIR / "sync-agent-skills.ps1", powershell),
            "-VerifyOnly",
        ],
        cwd=REPO_ROOT,
    )
    return {
        "ok": result.returncode == 0,
        "status": "ready" if result.returncode == 0 else "failed",
        "exitCode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def dev_stack_status(args: argparse.Namespace) -> int:
    python_name = Path(sys.executable).name if sys.executable else "python"
    powershell = powershell_executable()
    manifest, manifest_error = load_manifest()
    managed_skills = []
    if manifest and isinstance(manifest.get("sources"), list):
        for source in manifest["sources"]:
            skill = str(source.get("skill", "")).strip()
            if skill:
                managed_skills.append(skill)

    commands = [
        command_status("git", ["git"], True, "repo and hook management"),
        command_status(python_name, [python_name, "python3", "python", "py"], True, "cross-platform tooling"),
        {
            "name": "powershell",
            "required": False,
            "purpose": "legacy scripts and pre-commit wrapper",
            "requested": ["pwsh", "pwsh.exe", "powershell", "powershell.exe"],
            "available": bool(powershell),
            "status": "ready" if powershell else "warning",
            "path": powershell,
        },
        command_status("rg", ["rg"], False, "fast repo scans"),
        {
            "name": "lua",
            "required": False,
            "purpose": "targeted Lua tests and schema helpers",
            "requested": ["lua", "luajit"],
            "available": bool(first_command(["lua", "luajit"])),
            "status": "ready" if first_command(["lua", "luajit"]) else "warning",
            "path": first_command(["lua", "luajit"]),
        },
        command_status("luacheck", ["luacheck"], False, "Lua lint gate"),
        command_status("stylua", ["stylua"], False, "Lua formatting gate"),
        {
            "name": "mech",
            "required": False,
            "purpose": "Mechanic-backed addon and docs checks",
            "requested": [default_mechanic_executable() or "mech"],
            "available": bool(default_mechanic_executable()),
            "status": "ready" if default_mechanic_executable() else "warning",
            "path": default_mechanic_executable(),
        },
    ]

    paths = [
        path_status("repoRoot", REPO_ROOT, True, directory=True),
        path_status("addonDir", ADDON_DIR, True, directory=True),
        path_status("skillsManifest", TOOLS_DIR / "agent-skills.manifest.json", True),
        path_status("mcpServer", TOOLS_DIR / "krt_mcp_server.py", True),
        path_status("legacyPreCommit", TOOLS_DIR / "pre-commit.ps1", True),
        path_status("localSkillsRoot", local_skills_root(), False, directory=True),
        path_status("mechanicRoot", default_mechanic_root(), False, directory=True),
    ]

    verification = verify_skills_if_requested(args.verify_skills)

    warnings = []
    if manifest_error:
        warnings.append({"code": "manifest_load_failed", "message": manifest_error})
    if not powershell:
        warnings.append(
            {
                "code": "powershell_missing",
                "message": "Some legacy scripts still require PowerShell. Core flows now use tools/krt.py.",
            }
        )
    if verification and verification.get("status") == "unavailable":
        warnings.append({"code": "skills_verify_unavailable", "message": verification["reason"]})

    payload = {
        "ok": True,
        "platform": sys.platform,
        "repoRoot": str(REPO_ROOT),
        "commands": commands,
        "paths": paths,
        "managedSkills": managed_skills,
        "warnings": warnings,
    }
    if verification is not None:
        payload["skillsVerification"] = verification

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    print(f"Repo: {payload['repoRoot']}")
    print(f"Platform: {payload['platform']}")
    print("")
    print("Commands:")
    for item in commands:
        location = item["path"] or "missing"
        print(f"  - {item['name']}: {item['status']} ({location})")
    print("")
    print("Paths:")
    for item in paths:
        location = item["path"]
        print(f"  - {item['name']}: {item['status']} ({location})")
    if managed_skills:
        print("")
        print("Managed skills:")
        for skill in managed_skills:
            print(f"  - {skill}")
    if verification is not None:
        print("")
        print(f"Skill verification: {verification.get('status')}")
        if verification.get("stdout"):
            print(verification["stdout"])
        if verification.get("stderr"):
            print(verification["stderr"], file=sys.stderr)
    if warnings:
        print("")
        print("Warnings:")
        for warning in warnings:
            print(f"  - {warning['code']}: {warning['message']}")
    return 0


def pre_commit(_: argparse.Namespace) -> int:
    return run_powershell_script("pre-commit.ps1", [])


def read_release_version_from_git_ref(ref: str) -> str | None:
    if not ref.strip():
        return None

    target = f"{ref}:!KRT/CHANGELOG.md"
    result = run_command_capture(["git", "show", target], cwd=REPO_ROOT)
    if result.returncode != 0:
        return None

    return extract_release_version_from_text(
        result.stdout,
        require_unreleased_release_version=False,
        source_label=target,
    )


def release_publish_gate(args: argparse.Namespace) -> int:
    payload = resolve_release_metadata()
    previous_ref = args.previous_ref.strip()
    previous_version = read_release_version_from_git_ref(previous_ref) if previous_ref else None
    previous_version_core = None
    if previous_version:
        previous_version_core, _ = parse_release_version(previous_version)

    should_publish = False
    reason = ""
    if not payload["publishable"]:
        reason = "Channel is internal-only and must not publish."
    elif not previous_version_core:
        should_publish = True
        reason = "No previous addon changelog version was found."
    elif previous_version_core == payload["version_core"]:
        reason = (
            "Numeric version is unchanged. "
            f"Current '{payload['version']}' vs previous '{previous_version}'."
        )
    else:
        should_publish = True
        reason = (
            "Numeric version changed. "
            f"Current '{payload['version']}' vs previous '{previous_version}'."
        )

    gate = {
        "should_publish": should_publish,
        "reason": reason,
        "current_version": payload["version"],
        "current_version_core": payload["version_core"],
        "current_channel": payload["channel"],
        "publishable": payload["publishable"],
        "previous_ref": previous_ref or None,
        "previous_version": previous_version,
        "previous_version_core": previous_version_core,
    }

    if args.github_output:
        write_github_output(args.github_output, gate)

    if args.json:
        print(json.dumps(gate, indent=2))
        return 0

    print(f"Should publish: {gate['should_publish']}")
    print(f"Reason: {gate['reason']}")
    return 0


def release_metadata(args: argparse.Namespace) -> int:
    expected_channel = args.expected_channel or None
    payload = resolve_release_metadata(expected_channel)

    if args.github_output:
        write_github_output(args.github_output, payload)

    if args.json:
        print(json.dumps(payload, indent=2))
        return 0

    print(f"Version: {payload['version']}")
    print(f"Version core: {payload['version_core']}")
    print(f"Channel: {payload['channel']}")
    print(f"Prerelease: {payload['prerelease']}")
    print(f"Publishable: {payload['publishable']}")
    print(f"Tag: {payload['tag']}")
    print(f"Asset: {payload['asset_name']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cross-platform KRT repo tooling")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_zip = subparsers.add_parser("build-release-zip", help="Build addon ZIP that contains only !KRT/")
    build_zip.add_argument("--output-dir", default="dist")
    build_zip.add_argument("--version", default="")
    build_zip.add_argument("--file-name", default="")
    build_zip.add_argument("--write-checksum", action="store_true")
    build_zip.set_defaults(handler=build_release_zip)

    install = subparsers.add_parser("install-hooks", help="Set git core.hooksPath=.githooks")
    install.set_defaults(handler=install_hooks)

    quality = subparsers.add_parser("repo-quality-check", help="Run one repo-local quality check script")
    quality.add_argument("--check", choices=sorted(REPO_CHECK_SCRIPTS), required=True)
    quality.set_defaults(handler=repo_quality_check)

    skills_list = subparsers.add_parser("skills-manifest", help="Print managed skills manifest")
    skills_list.add_argument("--json", action="store_true")
    skills_list.set_defaults(handler=skills_manifest)

    skills = subparsers.add_parser("skills-sync", help="Run vendored skill sync or verification")
    skills.add_argument("--verify-only", action="store_true")
    skills.add_argument("--install-local", action="store_true")
    skills.add_argument("--local-skills-root", default="")
    skills.set_defaults(handler=skills_sync)

    bootstrap = subparsers.add_parser("mechanic-bootstrap", help="Bootstrap/update local Mechanic checkout")
    bootstrap.add_argument("--mechanic-root", default="")
    bootstrap.add_argument("--repo-url", default="")
    bootstrap.add_argument("--ref", default="")
    bootstrap.add_argument("--pull", action="store_true")
    bootstrap.add_argument("--skip-pip-upgrade", action="store_true")
    bootstrap.add_argument("--run-setup-tools", action="store_true")
    bootstrap.set_defaults(handler=mechanic_bootstrap)

    mcp = subparsers.add_parser("run-krt-mcp", help="Start the repo-local MCP server")
    mcp.add_argument("--python-exe", default="")
    mcp.set_defaults(handler=run_krt_mcp)

    mech = subparsers.add_parser("mech", help="Call Mechanic with KRT defaults")
    mech.add_argument("action", choices=MECHANIC_ACTIONS)
    mech.add_argument("--mechanic-exe", default="")
    mech.add_argument("--addon-name", default="!KRT")
    mech.add_argument("--addon-path", default="")
    mech.add_argument("--json", action="store_true")
    mech.add_argument("--agent-mode", action="store_true")
    mech.add_argument("--include-suspicious", action="store_true")
    mech.add_argument("--format-check", action="store_true")
    mech.add_argument("--categories", default="")
    mech.add_argument("--min-severity", default="warning")
    mech.set_defaults(handler=mechanic)

    status = subparsers.add_parser("dev-stack-status", help="Inspect repo tooling readiness")
    status.add_argument("--json", action="store_true")
    status.add_argument("--verify-skills", action="store_true")
    status.set_defaults(handler=dev_stack_status)

    release = subparsers.add_parser(
        "release-metadata",
        help="Resolve release version, channel, and tag from !KRT/CHANGELOG.md and !KRT/!KRT.toc",
    )
    release.add_argument("--expected-channel", choices=("alpha", "beta", "release"), default="")
    release.add_argument("--json", action="store_true")
    release.add_argument("--github-output", default="")
    release.set_defaults(handler=release_metadata)

    release_gate = subparsers.add_parser(
        "release-publish-gate",
        help="Decide whether a publish is allowed by comparing current and previous numeric versions",
    )
    release_gate.add_argument("--previous-ref", default="")
    release_gate.add_argument("--json", action="store_true")
    release_gate.add_argument("--github-output", default="")
    release_gate.set_defaults(handler=release_publish_gate)

    pre = subparsers.add_parser("pre-commit", help="Run the canonical pre-commit entrypoint")
    pre.set_defaults(handler=pre_commit)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.handler(args))
    except CliError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
