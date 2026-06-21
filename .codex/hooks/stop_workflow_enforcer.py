#!/usr/bin/env python3
"""Continue turns that end without the required 55to53 workflow signals."""

from __future__ import annotations

import json
import sys
from pathlib import Path


STATE_DIR = Path(__file__).resolve().parent / "state"


def main() -> int:
    payload = json.load(sys.stdin)
    session_id = payload.get("session_id", "unknown")
    stop_hook_active = bool(payload.get("stop_hook_active", False))
    last_message = (payload.get("last_assistant_message") or "").lower()
    state_path = STATE_DIR / f"{session_id}.json"

    if stop_hook_active or not state_path.is_file():
        json.dump({"continue": True}, sys.stdout)
        return 0

    state = json.loads(state_path.read_text(encoding="utf-8"))
    if state.get("classification") != "complex-orchestrated":
        json.dump({"continue": True}, sys.stdout)
        return 0

    if not last_message:
        json.dump({"continue": True}, sys.stdout)
        return 0

    signals = {
        "spark": "spark_implementer" in last_message or "spark implementer" in last_message,
        "plan": "mini plan" in last_message or "plan followed" in last_message,
        "checks": "tests/checks run" in last_message or "checks run" in last_message,
    }
    missing = [name for name, present in signals.items() if not present]
    if not missing:
        json.dump({"continue": True}, sys.stdout)
        return 0

    reason = (
        "Complex 55to53 task ended without the required workflow signals. "
        "Continue and ensure the response shows parent plan, Spark delegation, "
        "and checks/run evidence before closing."
    )
    json.dump({"decision": "block", "reason": reason}, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
