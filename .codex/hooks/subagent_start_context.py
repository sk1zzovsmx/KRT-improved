#!/usr/bin/env python3
"""Inject role-specific context into KRT subagents."""

from __future__ import annotations

import json
import sys


def main() -> int:
    payload = json.load(sys.stdin)
    agent_type = payload.get("agent_type", "")

    if agent_type == "spark_implementer":
        context = (
            "KRT subagent guardrail: implementation only. Follow the parent plan "
            "exactly, keep diffs minimal, avoid design decisions, and report any "
            "scope expansion instead of improvising."
        )
    elif agent_type == "code-mapper":
        context = (
            "KRT subagent guardrail: exploration only. Map ownership, call paths, "
            "branch points, and unknowns. Do not edit and do not redesign."
        )
    else:
        context = "KRT subagent guardrail: preserve the assigned role and avoid scope drift."

    json.dump(
        {
            "systemMessage": f"KRT subagent role reinforcement for {agent_type}",
            "hookSpecificOutput": {
                "hookEventName": "SubagentStart",
                "additionalContext": context,
            },
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
