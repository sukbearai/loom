# How Codex-Vault Works

## The Core Loop

Codex-Vault gives LLM agents persistent memory through a simple loop:

```
Session N: agent reads vault → works with you → writes notes → git commit
Session N+1: agent reads vault (with N's notes) → continues where you left off
```

No databases, no embeddings, no cloud services. Just markdown files and git.

## Three Hooks

The entire automation layer is 3 hook scripts:

### 1. session-start.py

Runs when the agent starts. Reads the vault and injects context into the agent's prompt:

- **North Star** — your goals (from `brain/North Star.md`)
- **Recent changes** — what happened in the last 48 hours (from `git log`)
- **Active work** — current projects (from `work/active/`)
- **Vault files** — complete file listing so the agent knows what exists

This is the "recall" step — the agent starts with context, not a blank slate.

### 2. classify-message.py

Runs on every user message. Scans for keywords and injects routing hints:

- "We decided to..." → hint: create a Decision Record
- "Shipped the feature" → hint: note the win
- "Sprint update" → hint: update the active work note

**Two modes** (configured via `.vault/.codex-vault/config.json` for integrated installs, `vault/.codex-vault/config.json` for standalone):

- **suggest** (default) — the agent suggests skills, you decide whether to run them
- **auto** — the agent executes skills immediately on intent detection

Session-end detection always stays in suggest mode for safety.

```json
{"classify_mode": "auto"}
```

### 3. validate-write.py

Runs after tool use, with agent-specific behavior:

- Claude Code: after writing or editing a `.md` file
- Codex CLI: after running Bash, to catch command/setup failures

For Claude Code note validation, it checks:

- Has YAML frontmatter? (date, description, tags)
- Has at least one `[[wikilink]]`?
- Is in the right folder?

If something's missing, the agent gets a warning and fixes it.

For Codex CLI Bash validation, it blocks hard setup failures such as missing commands and permission errors. Ordinary command failures, including test failures and missing input files, stay in the Bash output for the agent to review without an extra hook block.

## The Vault

Eight folders, five note types:

- `brain/` — persistent memory (goals, decisions, patterns)
- `work/active/` — current projects
- `work/archive/` — completed projects
- `templates/` — note templates with YAML frontmatter
- `thinking/` — scratchpad (promote findings, then delete)
- `sources/` — raw source documents (immutable)
- `reference/` — saved answers and analyses
- `Home.md` — entry point

## Why Markdown + Git

- **Portable** — works with any editor, any agent, any OS
- **Auditable** — `git log` shows exactly what changed and when
- **Durable** — survives agent changes, service shutdowns, API deprecations
- **Composable** — Obsidian for visual browsing, grep for search, git for history

## CLI

Install, upgrade, and uninstall via npm:

```bash
npx @suwujs/codex-vault init        # Install
npx @suwujs/codex-vault upgrade     # Upgrade hooks/skills (preserves data)
npx @suwujs/codex-vault uninstall   # Remove hooks/skills (preserves data)
```

The CLI is a thin wrapper around `plugin/install.sh`. It adds version tracking (`.vault/.codex-vault/version` for integrated installs, `vault/.codex-vault/version` for standalone), backup on upgrade, and precise cleanup on uninstall.

## Why Hooks (Not RAG)

RAG re-derives knowledge from scratch on every query. Codex-Vault compiles knowledge once (into structured notes with links) and keeps it current. The agent reads the compiled wiki, not raw chunks.

Hooks are the key mechanism because they're:
- **Agent-agnostic** — Claude Code and Codex CLI both use lifecycle hooks, with agent-specific event capabilities where needed
- **Zero infrastructure** — shell scripts, no servers
- **Transparent** — you can read every hook, modify them, add your own
