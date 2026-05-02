#!/usr/bin/env python3
"""PostToolUse hook for Codex CLI — Bash command validation.

Checks Bash command output for hard setup failures only: missing
commands and permission problems. Ordinary command failures, such as
test failures or missing input files, are left for the agent to review
from the Bash output without an extra hook block.

Codex only supports additionalContext on context-producing events. This
tool hook returns decision/reason only so it remains valid even as Codex
strictly validates PreToolUse/PostToolUse output schemas.
"""
import json
import re
import sys


HARD_FAILURE_PATTERNS = re.compile(
    r"command not found|permission denied",
    re.IGNORECASE,
)


def _safe_string(value):
    return value if isinstance(value, str) else ""


def _parse_tool_response(raw):
    """Try to parse tool_response as JSON dict."""
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                return parsed
        except (ValueError, TypeError):
            pass
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    hook_event_name = payload.get("hook_event_name") or payload.get("hookEventName")
    if hook_event_name and hook_event_name != "PostToolUse":
        sys.exit(0)

    tool_name = _safe_string(payload.get("tool_name", "")).strip()
    if tool_name != "Bash":
        sys.exit(0)

    # Extract command and response
    tool_input = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    command = _safe_string(tool_input.get("command", "")).strip()

    raw_response = payload.get("tool_response")
    parsed = _parse_tool_response(raw_response)

    stdout_text = ""
    stderr_text = ""

    if parsed:
        stdout_text = _safe_string(parsed.get("stdout", "")).strip()
        stderr_text = _safe_string(parsed.get("stderr", "")).strip()
    else:
        stdout_text = _safe_string(raw_response).strip()

    combined = f"{stderr_text}\n{stdout_text}".strip()
    if not combined:
        sys.exit(0)

    # Check for hard failures
    if HARD_FAILURE_PATTERNS.search(combined):
        output = {
            "decision": "block",
            "reason": "Bash output indicates a command/setup failure that should be fixed before retrying.",
        }
        sys.stdout.write(json.dumps(output) + "\n")
        sys.stdout.flush()
        sys.exit(0)

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
