#!/usr/bin/env python3
"""Repo-local MCP server for KRT skill and addon development workflows."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


SERVER_NAME = "krt-dev-tools"
SERVER_VERSION = "0.1.0"
DEFAULT_PROTOCOL_VERSION = "2025-06-18"

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = REPO_ROOT / "tools"

REPO_CHECKS = {
    "toc_files": "check-toc-files.ps1",
    "lua_syntax": "check-lua-syntax.ps1",
    "ui_binding": "check-ui-binding.ps1",
    "layering": "check-layering.ps1",
    "raid_hardening": "check-raid-hardening.ps1",
    "lua_uniformity": "check-lua-uniformity.ps1",
}

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


class ToolError(Exception):
    """Raised for invalid MCP tool inputs."""


@dataclass
class ToolSpec:
    name: str
    description: str
    input_schema: dict[str, Any]
    handler: Callable[[dict[str, Any]], dict[str, Any]]
    annotations: dict[str, Any] | None = None

    def to_mcp(self) -> dict[str, Any]:
        payload = {
            "name": self.name,
            "description": self.description,
            "inputSchema": self.input_schema,
        }
        if self.annotations:
            payload["annotations"] = self.annotations
        return payload


class McpIo:
    """Handles MCP stdio framing, with support for current and legacy styles."""

    def __init__(self) -> None:
        self._mode: str | None = None
        self._stdin = sys.stdin.buffer
        self._stdout = sys.stdout.buffer

    def read_message(self) -> dict[str, Any] | None:
        if self._mode == "header":
            return self._read_header_message()

        while True:
            first_line = self._stdin.readline()
            if not first_line:
                return None
            if not first_line.strip():
                continue
            if first_line.lower().startswith(b"content-length:"):
                self._mode = "header"
                return self._read_header_message(first_line)

            self._mode = "line"
            return self._decode_json(first_line)

    def write_message(self, message: dict[str, Any]) -> None:
        body = json.dumps(message, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
        if self._mode == "header":
            header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
            self._stdout.write(header)
            self._stdout.write(body)
        else:
            self._stdout.write(body + b"\n")
        self._stdout.flush()

    def _read_header_message(self, first_line: bytes | None = None) -> dict[str, Any]:
        headers = {}
        line = first_line
        while True:
            if line is None:
                line = self._stdin.readline()
            if not line:
                return None
            if line in (b"\r\n", b"\n"):
                break
            decoded = line.decode("ascii", errors="replace")
            key, _, value = decoded.partition(":")
            headers[key.strip().lower()] = value.strip()
            line = None

        length_text = headers.get("content-length")
        if not length_text:
            raise ValueError("Missing Content-Length header.")

        length = int(length_text)
        body = self._stdin.read(length)
        if len(body) != length:
            raise ValueError("Unexpected EOF while reading MCP body.")

        return self._decode_json(body)

    @staticmethod
    def _decode_json(payload: bytes) -> dict[str, Any]:
        try:
            return json.loads(payload.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON payload: {exc}") from exc


def validate_keys(arguments: dict[str, Any], allowed: set[str]) -> None:
    extra = sorted(set(arguments) - allowed)
    if extra:
        raise ToolError(f"Unexpected arguments: {', '.join(extra)}")


def expect_bool(arguments: dict[str, Any], key: str, default: bool = False) -> bool:
    value = arguments.get(key, default)
    if not isinstance(value, bool):
        raise ToolError(f"'{key}' must be a boolean.")
    return value


def expect_string(arguments: dict[str, Any], key: str, *, required: bool = False) -> str | None:
    value = arguments.get(key)
    if value is None:
        if required:
            raise ToolError(f"Missing required argument: {key}")
        return None
    if not isinstance(value, str) or not value.strip():
        raise ToolError(f"'{key}' must be a non-empty string.")
    return value.strip()


def expect_enum(arguments: dict[str, Any], key: str, values: tuple[str, ...] | list[str]) -> str:
    value = expect_string(arguments, key, required=True)
    if value not in values:
        allowed = ", ".join(values)
        raise ToolError(f"'{key}' must be one of: {allowed}")
    return value


def powershell_exe() -> str:
    return os.environ.get("KRT_POWERSHELL_EXE", "powershell")


def truncate_text(text: str, limit: int = 5000) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + "\n...[truncated]"


def maybe_parse_json(text: str) -> Any | None:
    stripped = text.strip()
    if not stripped:
        return None
    if not stripped.startswith(("{", "[")):
        return None
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        return None


def run_powershell(script_name: str, args: list[str]) -> dict[str, Any]:
    command = [
        powershell_exe(),
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(TOOLS_DIR / script_name),
    ]
    command.extend(args)

    try:
        completed = subprocess.run(
            command,
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except FileNotFoundError as exc:
        return {
            "ok": False,
            "exitCode": None,
            "command": command,
            "stdout": "",
            "stderr": str(exc),
        }

    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    result: dict[str, Any] = {
        "ok": completed.returncode == 0,
        "exitCode": completed.returncode,
        "command": command,
        "stdout": stdout,
        "stderr": stderr,
    }

    parsed = maybe_parse_json(stdout)
    if parsed is not None:
        result["parsedJson"] = parsed

    return result


def render_result_text(result: dict[str, Any]) -> str:
    lines = [
        f"ok: {result.get('ok')}",
        f"exitCode: {result.get('exitCode')}",
    ]
    stdout = result.get("stdout") or ""
    stderr = result.get("stderr") or ""
    if stdout:
        lines.append("stdout:")
        lines.append(truncate_text(stdout))
    if stderr:
        lines.append("stderr:")
        lines.append(truncate_text(stderr))
    return "\n".join(lines)


def make_tool_response(data: dict[str, Any], *, is_error: bool = False) -> dict[str, Any]:
    text = render_result_text(data) if "exitCode" in data else truncate_text(json.dumps(data, indent=2))
    response = {
        "content": [{"type": "text", "text": text}],
        "structuredContent": data,
    }
    if is_error:
        response["isError"] = True
    return response


def handle_skills_manifest(arguments: dict[str, Any]) -> dict[str, Any]:
    validate_keys(arguments, set())
    manifest_path = TOOLS_DIR / "agent-skills.manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sources = []
    for source in manifest.get("sources", []):
        row = dict(source)
        row["destinationFullPath"] = str(REPO_ROOT / source["destinationPath"])
        sources.append(row)
    return {
        "ok": True,
        "manifestVersion": manifest.get("version"),
        "manifestPath": str(manifest_path),
        "sources": sources,
    }


def handle_skills_verify(arguments: dict[str, Any]) -> dict[str, Any]:
    validate_keys(arguments, set())
    return run_powershell("sync-agent-skills.ps1", ["-VerifyOnly"])


def handle_skills_sync(arguments: dict[str, Any]) -> dict[str, Any]:
    validate_keys(arguments, {"installLocal", "localSkillsRoot"})
    install_local = expect_bool(arguments, "installLocal", default=False)
    local_skills_root = expect_string(arguments, "localSkillsRoot")

    args = []
    if install_local:
        args.append("-InstallLocal")
    if local_skills_root:
        args.extend(["-LocalSkillsRoot", local_skills_root])
    return run_powershell("sync-agent-skills.ps1", args)


def handle_repo_quality_check(arguments: dict[str, Any]) -> dict[str, Any]:
    validate_keys(arguments, {"check"})
    check_name = expect_enum(arguments, "check", list(REPO_CHECKS))
    return run_powershell(REPO_CHECKS[check_name], [])


def handle_mechanic_call(arguments: dict[str, Any]) -> dict[str, Any]:
    validate_keys(
        arguments,
        {
            "action",
            "agentMode",
            "jsonOutput",
            "includeSuspicious",
            "formatCheck",
            "categories",
            "minSeverity",
            "mechanicExe",
            "addonName",
            "addonPath",
        },
    )
    action = expect_enum(arguments, "action", list(MECHANIC_ACTIONS))
    agent_mode = expect_bool(arguments, "agentMode", default=(action == "AddonOutput"))
    json_output = expect_bool(arguments, "jsonOutput", default=(action != "AddonOutput"))
    include_suspicious = expect_bool(arguments, "includeSuspicious", default=False)
    format_check = expect_bool(arguments, "formatCheck", default=False)
    categories = expect_string(arguments, "categories")
    min_severity = expect_string(arguments, "minSeverity")
    mechanic_exe = expect_string(arguments, "mechanicExe")
    addon_name = expect_string(arguments, "addonName")
    addon_path = expect_string(arguments, "addonPath")

    if action != "AddonOutput" and agent_mode:
        raise ToolError("'agentMode' is only valid for action='AddonOutput'.")
    if agent_mode and json_output:
        raise ToolError("'agentMode' and 'jsonOutput' cannot both be true.")

    args = ["-Action", action]
    if json_output:
        args.append("-Json")
    if agent_mode:
        args.append("-AgentMode")
    if include_suspicious:
        args.append("-IncludeSuspicious")
    if format_check:
        args.append("-FormatCheck")
    if categories:
        args.extend(["-Categories", categories])
    if min_severity:
        args.extend(["-MinSeverity", min_severity])
    if mechanic_exe:
        args.extend(["-MechanicExe", mechanic_exe])
    if addon_name:
        args.extend(["-AddonName", addon_name])
    if addon_path:
        args.extend(["-AddonPath", addon_path])

    return run_powershell("mech-krt.ps1", args)


TOOLS = {
    spec.name: spec
    for spec in [
        ToolSpec(
            name="skills_manifest",
            description=(
                "Read the pinned skill manifest used to vendor .agents/skills. "
                "Use this before syncing or installing local skills."
            ),
            input_schema={
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
            handler=handle_skills_manifest,
            annotations={"readOnlyHint": True},
        ),
        ToolSpec(
            name="skills_verify",
            description=(
                "Verify that vendored skills exactly match the manifest-pinned upstream snapshots. "
                "Read-only check."
            ),
            input_schema={
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
            handler=handle_skills_verify,
            annotations={"readOnlyHint": True},
        ),
        ToolSpec(
            name="skills_sync",
            description=(
                "Sync vendored skills from the manifest-pinned upstream snapshots. "
                "Optionally install them into a local Codex skills directory."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "installLocal": {"type": "boolean", "default": False},
                    "localSkillsRoot": {"type": "string"},
                },
                "additionalProperties": False,
            },
            handler=handle_skills_sync,
            annotations={"destructiveHint": True},
        ),
        ToolSpec(
            name="repo_quality_check",
            description=(
                "Run one of the repo-local addon quality checks from tools/. "
                "These scripts do not require Mechanic."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "check": {
                        "type": "string",
                        "enum": list(REPO_CHECKS),
                    }
                },
                "required": ["check"],
                "additionalProperties": False,
            },
            handler=handle_repo_quality_check,
            annotations={"readOnlyHint": True},
        ),
        ToolSpec(
            name="mechanic_call",
            description=(
                "Run the existing Mechanic wrapper for KRT. "
                "Requires Mechanic to be bootstrapped locally first."
            ),
            input_schema={
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": list(MECHANIC_ACTIONS)},
                    "agentMode": {"type": "boolean"},
                    "jsonOutput": {"type": "boolean"},
                    "includeSuspicious": {"type": "boolean"},
                    "formatCheck": {"type": "boolean"},
                    "categories": {"type": "string"},
                    "minSeverity": {"type": "string"},
                    "mechanicExe": {"type": "string"},
                    "addonName": {"type": "string"},
                    "addonPath": {"type": "string"},
                },
                "required": ["action"],
                "additionalProperties": False,
            },
            handler=handle_mechanic_call,
        ),
    ]
}


def make_error_response(error_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": error_id,
        "error": {
            "code": code,
            "message": message,
        },
    }


def handle_request(method: str, params: dict[str, Any]) -> dict[str, Any]:
    if method == "initialize":
        protocol_version = params.get("protocolVersion")
        if not isinstance(protocol_version, str) or not protocol_version.strip():
            protocol_version = DEFAULT_PROTOCOL_VERSION
        return {
            "protocolVersion": protocol_version,
            "capabilities": {"tools": {}},
            "serverInfo": {
                "name": SERVER_NAME,
                "version": SERVER_VERSION,
            },
            "instructions": (
                "Use skills_manifest or skills_verify first, then repo_quality_check or "
                "mechanic_call depending on whether Mechanic is installed."
            ),
        }

    if method == "ping":
        return {}

    if method == "tools/list":
        return {"tools": [tool.to_mcp() for tool in TOOLS.values()]}

    if method == "tools/call":
        name = params.get("name")
        if not isinstance(name, str) or not name:
            raise ToolError("Missing tool name.")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            raise ToolError("'arguments' must be an object.")
        tool = TOOLS.get(name)
        if tool is None:
            raise ToolError(f"Unknown tool: {name}")
        result = tool.handler(arguments)
        return make_tool_response(result, is_error=not result.get("ok", True))

    raise ToolError(f"Method not supported: {method}")


def main() -> int:
    transport = McpIo()
    while True:
        try:
            message = transport.read_message()
        except Exception as exc:
            transport.write_message(make_error_response(None, -32700, str(exc)))
            return 1

        if message is None:
            return 0

        request_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}

        if not isinstance(method, str):
            if request_id is not None:
                transport.write_message(make_error_response(request_id, -32600, "Missing method name."))
            continue

        if not isinstance(params, dict):
            if request_id is not None:
                transport.write_message(make_error_response(request_id, -32602, "'params' must be an object."))
            continue

        if request_id is None:
            if method == "notifications/initialized":
                continue
            if method == "exit":
                return 0
            continue

        try:
            result = handle_request(method, params)
        except ToolError as exc:
            transport.write_message(make_error_response(request_id, -32602, str(exc)))
            continue
        except Exception as exc:
            transport.write_message(make_error_response(request_id, -32603, str(exc)))
            continue

        transport.write_message({
            "jsonrpc": "2.0",
            "id": request_id,
            "result": result,
        })


if __name__ == "__main__":
    raise SystemExit(main())
