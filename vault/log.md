---
date: "{{date}}"
description: "Chronological log of vault operations — ingests, queries, session starts, maintenance"
tags:
  - index
---

# Log

Append-only record of vault operations. Each entry starts with `## [YYYY-MM-DD] <type> | <title>` for easy parsing with grep.

Entry types: `ingest`, `session`, `query`, `maintenance`, `decision`, `archive`.

## [2026-04-06] session | Initial vault setup
- Created vault structure
- Configured hooks for Claude Code and Codex CLI
