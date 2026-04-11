---
name: lint
description: "Vault health check — scans for orphan pages, broken links, stale content, missing frontmatter, index drift, and more. Triggers: 'lint', 'health check', 'vault check', 'audit vault', 'check vault health'."
license: MIT
metadata:
  author: sukbearai
  version: "1.0.0"
  homepage: "https://github.com/sukbearai/codex-vault"
---

Run a full health check on the vault. Execute each check below, collect findings into three severity buckets, then output a single report.

### Step 0: Context Check
Confirm session-start context is loaded (North Star, recent changes). If first vault skill use this session, read `work/Index.md` and `SCHEMA.md`.

### Setup

Determine the vault root (directory containing `Home.md` and `brain/`). All paths below are relative to the vault root.

Build a file inventory: use Glob to list all `.md` files in the vault, excluding `.codex-vault/`, `.claude/`, `.codex/`, and `templates/`. Store this list for reuse across checks.

### Check 1 — Broken Links (severity: red)

Grep all `.md` files for `[[...]]` wikilinks. For each unique link target:
- Derive the expected filename: `<target>.md` (search across all vault directories).
- If no matching file exists, record: the source file, the broken link text, and which line.

### Check 2 — Orphan Pages (severity: yellow)

Using the same wikilink scan from Check 1, build an inbound-link map (which files are linked TO).

A page is orphan if it has **zero inbound links**. Exclude these from orphan detection:
- `Home.md`, `work/Index.md`, `SCHEMA.md`, `log.md`, `CLAUDE.md`, `AGENTS.md`
- Everything under `templates/` or `sources/`

### Check 3 — Index Completeness (severity: yellow)

Read `work/Index.md`. List all `[[...]]` links in it.

Compare against actual files in `work/active/` and `work/archive/`:
- Files present on disk but NOT linked in Index.md → "missing from index"
- Links in Index.md pointing to files that don't exist → "stale index entry" (also caught by Check 1)

### Check 4 — Frontmatter Validation (severity: yellow)

For each `.md` file (excluding `templates/`, `sources/`, `Home.md`, `log.md`, `SCHEMA.md`, `CLAUDE.md`, `AGENTS.md`):
- Read the first 10 lines.
- Check for YAML frontmatter delimited by `---`.
- Verify that `date`, `tags`, and `description` fields are present and non-empty.
- Record any file missing one or more required fields.

### Check 5 — Stale Content (severity: info)

For each file with a valid `date` field in frontmatter:
- Parse the date value.
- If the date is more than 90 days before today, record as stale.
- Report the file path and how many days since last update.

### Check 6 — Oversized Pages (severity: yellow)

Count lines in each `.md` file. If a file exceeds 200 lines, record it with its line count.

### Check 7 — Tag Audit (severity: info)

Collect all `tags` values from every file's frontmatter. Build a sorted list of unique tags with usage counts.

If `SCHEMA.md` exists at the vault root, read its declared tag list. Report any tags in use but not declared in the schema, and any declared tags with zero usage.

### Check 8 — Log Check (severity: info)

Read `log.md`. Count the number of `## ` heading entries. Report the total count.

### Check 9 — Index Bloat (severity: info, extension)

Re-read `work/Index.md`. Split it by `## ` headings into sections. If any section contains more than 50 `[[...]]` links, recommend grouping entries by first letter.

### Check 10 — Log Rotation (severity: info, extension)

If the log entry count from Check 8 exceeds 500, recommend rotating old entries to `log-YYYY.md`.

### Check 11 — Split Suggestions (severity: info, extension)

For each file flagged as oversized in Check 6:
- Read its `## ` headings.
- Suggest splitting into sub-notes based on the heading structure.

### Check 12 — Archive Integrity (severity: yellow)

- Verify that files in `work/archive/` are referenced in the Archive section of `work/Index.md`
- Check if any `[[wikilinks]]` in `work/active/` files point to pages that have been moved to `work/archive/`

### Check 13 — Topic Map (severity: info, extension)

- If the vault contains more than 200 `.md` files and `_meta/topic-map.md` does not exist, suggest creating a topic map for high-level navigation by subject area

### Output Report

Compile all findings into this format:

```
Vault Health Report

RED — Must Fix
  (list broken links with source file, link text, and line)

YELLOW — Should Fix
  (list orphan pages, index gaps, frontmatter issues, oversized pages, archive integrity)

BLUE — Info
  (tag stats, log entry count, stale content, page/template counts)

Extension Suggestions
  (index bloat, log rotation, split suggestions, topic map)

Passed: (list checks with zero findings)
```

If a severity bucket has no findings, show it as passed. End with a one-line vault summary: total files, total links, total tags.
