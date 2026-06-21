#!/usr/bin/env python3
"""Wrapper to launch the MarkItDown MCP server from repo-local environment."""

import os
import shutil
import sys


def main():
    repo_root = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(repo_root)

    if os.name == "nt":
        local_executable = os.path.join(repo_root, ".venv", "Scripts", "markitdown-mcp.exe")
    else:
        local_executable = os.path.join(repo_root, ".venv", "bin", "markitdown-mcp")

    if os.path.isfile(local_executable):
        args = [local_executable]
        args.extend(sys.argv[1:])
        os.execv(local_executable, args)

    from_path = shutil.which("markitdown-mcp")
    if not from_path:
        sys.stderr.write(
            "markitdown-mcp not found. Create a virtualenv and install deps:\n"
            "  py -3 -m venv .venv\n"
            "  .venv\\Scripts\\python.exe -m pip install -r tools/requirements-mcp.txt\n"
        )
        raise SystemExit(127)

    args = ["markitdown-mcp"]
    args.extend(sys.argv[1:])
    os.execvp("markitdown-mcp", args)


if __name__ == "__main__":
    main()
