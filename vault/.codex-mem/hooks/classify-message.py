#!/usr/bin/env python3
"""Classify user messages and inject routing hints.

Lightweight version: 5 core signals + session-end vault integrity check.
Agent-agnostic — outputs hookSpecificOutput compatible with both
Claude Code and Codex CLI.
"""
import json
import os
import subprocess
import sys
import re
from pathlib import Path


SIGNALS = [
    {
        "name": "DECISION",
        "message": "DECISION detected — suggest the user run /dump to capture this decision",
        "patterns": [
            "decided", "deciding", "decision", "we chose", "agreed to",
            "let's go with", "the call is", "we're going with",
        ],
    },
    {
        "name": "WIN",
        "message": "WIN detected — suggest the user run /dump to record this achievement",
        "patterns": [
            "achieved", "won", "praised",
            "kudos", "shoutout", "great feedback", "recognized",
        ],
    },
    {
        "name": "PROJECT UPDATE",
        "message": "PROJECT UPDATE detected — suggest the user run /dump to log this progress",
        "patterns": [
            "project update", "sprint", "milestone",
            "shipped", "shipping", "launched", "launching",
            "completed", "completing", "released", "releasing",
            "deployed", "deploying",
            "went live", "rolled out", "merged", "cut the release",
        ],
    },
    {
        "name": "QUERY",
        "message": "QUERY detected — suggest the user run /recall to check existing knowledge first",
        "patterns": [
            "what is", "how does", "why did", "compare", "analyze",
            "explain the", "what's the difference", "summarize the",
            "relationship between",
        ],
    },
    {
        "name": "INGEST",
        "message": "INGEST detected — suggest the user run /ingest to process the source",
        "patterns": [
            "ingest", "process this", "read this article",
            "summarize this", "new source", "clip this", "web clip",
        ],
    },
]

SESSION_END_PATTERNS = [
    "wrap up", "wrapping up", "that's all", "that's it",
    "done for now", "done for today", "i'm done", "call it a day",
    "end session", "bye", "goodbye", "good night", "see you",
    "结束", "收工", "今天到这", "就这样",
]


def _match(patterns, text):
    for phrase in patterns:
        if re.search(r'(?<![a-zA-Z])' + re.escape(phrase) + r'(?![a-zA-Z])', text):
            return True
    return False


def _find_vault_root():
    """Find vault root from CWD — check for Home.md/brain/, then vault/ subdir."""
    cwd = os.environ.get("CLAUDE_PROJECT_DIR",
           os.environ.get("CODEX_PROJECT_DIR", os.getcwd()))
    if os.path.isfile(os.path.join(cwd, "Home.md")) or os.path.isdir(os.path.join(cwd, "brain")):
        return cwd
    vault_sub = os.path.join(cwd, "vault")
    if os.path.isdir(vault_sub) and (
        os.path.isfile(os.path.join(vault_sub, "Home.md")) or
        os.path.isdir(os.path.join(vault_sub, "brain"))
    ):
        return vault_sub
    return None


def _get_changed_files(vault_root):
    """Get list of changed/new .md files relative to vault root."""
    files = set()
    try:
        # Staged + unstaged changes
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True, text=True, cwd=vault_root, timeout=5,
        )
        for f in result.stdout.strip().splitlines():
            if f.endswith(".md"):
                files.add(f)

        # Untracked files
        result = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            capture_output=True, text=True, cwd=vault_root, timeout=5,
        )
        for f in result.stdout.strip().splitlines():
            if f.endswith(".md"):
                files.add(f)
    except Exception:
        pass
    return files


def _check_vault_integrity(vault_root):
    """Check for common memory-write omissions."""
    warnings = []
    changed = _get_changed_files(vault_root)
    if not changed:
        return warnings

    # Check 1: New work notes but Index.md not updated
    new_work = [f for f in changed if f.startswith("work/active/") and f != "work/Index.md"]
    index_updated = "work/Index.md" in changed
    if new_work and not index_updated:
        names = ", ".join(os.path.basename(f).replace(".md", "") for f in new_work)
        warnings.append(f"New work notes ({names}) but work/Index.md not updated")

    # Check 2: Decision content written but brain/Key Decisions.md not updated
    decision_keywords = ["decided", "decision", "agreed to", "we chose", "the call is"]
    brain_decisions_updated = "brain/Key Decisions.md" in changed
    if not brain_decisions_updated:
        for f in changed:
            if f.endswith(".md") and not f.startswith("brain/"):
                try:
                    content = Path(os.path.join(vault_root, f)).read_text(encoding="utf-8").lower()
                    if any(kw in content for kw in decision_keywords):
                        warnings.append(
                            f"'{f}' contains decision content but brain/Key Decisions.md not updated"
                        )
                        break
                except Exception:
                    pass

    # Check 3: Pattern content written but brain/Patterns.md not updated
    pattern_keywords = ["pattern", "convention", "always do", "never do", "recurring"]
    brain_patterns_updated = "brain/Patterns.md" in changed
    if not brain_patterns_updated:
        for f in changed:
            if f.endswith(".md") and not f.startswith("brain/"):
                try:
                    content = Path(os.path.join(vault_root, f)).read_text(encoding="utf-8").lower()
                    if any(kw in content for kw in pattern_keywords):
                        warnings.append(
                            f"'{f}' contains pattern content but brain/Patterns.md not updated"
                        )
                        break
                except Exception:
                    pass

    # Check 4: operation log not updated after significant changes
    log_updated = "log.md" in changed
    significant_changes = len([f for f in changed
                               if f.startswith(("work/", "reference/", "brain/"))]) >= 2
    if significant_changes and not log_updated:
        warnings.append("Multiple vault changes but log.md not updated")

    return warnings


def classify(prompt):
    p = prompt.lower()
    return [s["message"] for s in SIGNALS if _match(s["patterns"], p)]


def is_session_end(prompt):
    p = prompt.lower()
    return _match(SESSION_END_PATTERNS, p)


def main():
    try:
        input_data = json.load(sys.stdin)
    except (ValueError, EOFError, OSError):
        sys.exit(0)

    prompt = input_data.get("prompt", "")
    if not isinstance(prompt, str) or not prompt:
        sys.exit(0)

    messages = []

    try:
        # Regular signal classification
        signals = classify(prompt)
        messages.extend(signals)

        # Session-end check
        if is_session_end(prompt):
            vault_root = _find_vault_root()
            if vault_root:
                integrity_warnings = _check_vault_integrity(vault_root)
                if integrity_warnings:
                    messages.append(
                        "SESSION END — vault integrity check found issues:\n"
                        + "\n".join(f"  - {w}" for w in integrity_warnings)
                        + "\nFix these before wrapping up."
                    )
                else:
                    messages.append("SESSION END — vault integrity check passed.")
    except Exception:
        sys.exit(0)

    if messages:
        hints = "\n".join(f"- {s}" for s in messages)
        output = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": (
                    "Skill suggestions (do NOT auto-execute — suggest the skill to the user and let them decide):\n"
                    + hints
                    + "\n\nWait for the user to invoke the skill. Do not create vault notes without explicit user action."
                )
            }
        }
        json.dump(output, sys.stdout)
        sys.stdout.flush()

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
