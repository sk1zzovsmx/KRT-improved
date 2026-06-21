#!/usr/bin/env python3
"""Classify prompt complexity and inject KRT workflow context."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


STATE_DIR = Path(__file__).resolve().parent / "state"


def classify_prompt(prompt: str) -> str:
    lowered = prompt.lower()
    bullet_count = len(re.findall(r"(?m)^\s*(?:[-*]|\d+\.)\s+", prompt))
    multi_file_cues = (
        "multi-file",
        "cross-module",
        "architecture",
        "orchestr",
        "workflow",
        "subagent",
        "review",
        "regression",
        "controller",
        "service",
        "module",
        "hook",
        "mcp",
        "refactor",
    )
    bounded_cues = (
        "fix",
        "implement",
        "add",
        "update",
        "change",
        "modify",
        "rename",
        "config",
        "docs",
    )

    if bullet_count >= 3 or any(cue in lowered for cue in multi_file_cues):
        return "complex-orchestrated"
    if any(cue in lowered for cue in bounded_cues):
        return "bounded"
    return "trivial"


def build_context(classification: str) -> str:
    if classification == "complex-orchestrated":
        return (
            "KRT workflow classifier: complex-orchestrated. Before editing, use the "
            "55to53 orchestrator rules. The parent should analyze, optionally use "
            "code-mapper, write a closed operational plan, delegate implementation "
            "to spark_implementer, and perform the final review."
        )
    if classification == "bounded":
        return (
            "KRT workflow classifier: bounded. The parent may edit directly only after "
            "writing a concise mini plan and keeping the diff narrowly scoped."
        )
    return (
        "KRT workflow classifier: trivial. The parent may edit directly if the change "
        "remains single-file, low-risk, and clearly owned."
    )


def main() -> int:
    payload = json.load(sys.stdin)
    session_id = payload.get("session_id", "unknown")
    turn_id = payload.get("turn_id", "unknown")
    prompt = payload.get("prompt", "")
    classification = classify_prompt(prompt)

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path = STATE_DIR / f"{session_id}.json"
    state_path.write_text(
        json.dumps(
            {
                "session_id": session_id,
                "turn_id": turn_id,
                "classification": classification,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    output = {
        "systemMessage": f"55to53 classifier: {classification}",
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": build_context(classification),
        },
    }
    json.dump(output, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
