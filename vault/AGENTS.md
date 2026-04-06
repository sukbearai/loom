# Codex-Mem — Core Instructions

A structured knowledge vault maintained by an LLM agent. You write notes, maintain links, and keep indexes current. The human curates sources, directs analysis, and asks questions.

## Vault Structure

| Folder | Purpose |
|--------|---------|
| `Home.md` | Vault entry point — quick links, current focus |
| `brain/` | Persistent memory — goals, decisions, patterns |
| `work/` | Work notes index (`Index.md`) |
| `work/active/` | Current projects (move to archive when done) |
| `work/archive/` | Completed work |
| `templates/` | Note templates with YAML frontmatter |
| `sources/` | Raw source documents — immutable, LLM reads only |
| `thinking/` | Scratchpad — promote findings, then delete |
| `reference/` | Saved answers and analyses from query writeback |

## Session Lifecycle

### Start

The SessionStart hook injects: North Star goals, recent git changes, active work, vault file listing. You start with context, not a blank slate.

### Work

1. The classify hook detects intent and suggests skills — **do not auto-execute**. Suggest the skill to the user and let them decide.
2. Available skills: `/dump`, `/recall`, `/ingest`, `/wrap-up`
3. Search before creating — check if a related note exists (use `/recall <topic>` for targeted vault search)
4. Update `work/Index.md` if a new note was created

### End

When the user says "wrap up" or similar:
1. Verify new notes have frontmatter and wikilinks
2. Update `work/Index.md` with any new or completed notes
3. Archive completed projects: move from `work/active/` to `work/archive/`
4. Check if `brain/` notes need updating with new decisions or patterns

## Creating Notes

1. **Always use YAML frontmatter**: `date`, `description` (~150 chars), `tags`
2. **Use templates** from `templates/`
3. **Place files correctly**: active work in `work/active/`, completed in `work/archive/`, source summaries in `work/active/` (tag: `source-summary`), drafts in `thinking/`
4. **Name files descriptively** — use the note title as filename

## Linking — Critical

**Graph-first.** Folders group by purpose, links group by meaning. A note lives in one folder but links to many notes.

**A note without links is a bug.** Every new note must link to at least one existing note via `[[wikilinks]]`.

Link syntax:
- `[[Note Title]]` — standard wikilink
- `[[Note Title|display text]]` — aliased
- `[[Note Title#Heading]]` — deep link

### When to Link

- Work note ↔ Decision Record (bidirectional)
- Index → all work notes
- North Star → active projects
- Memories → source notes

## Memory System

All persistent memory lives in `brain/`:

| File | Stores |
|------|--------|
| `North Star.md` | Goals and focus areas — read every session |
| `Memories.md` | Index of memory topics |
| `Key Decisions.md` | Decisions worth recalling across sessions |
| `Patterns.md` | Recurring patterns discovered across work |

When asked to "remember" something: write to the appropriate `brain/` file with a wikilink to context.

## Sources & Ingest

`sources/` holds raw source documents (articles, papers, web clips). This is the immutable layer — the agent reads from it but never modifies source files.

- Drop raw files into `sources/` (markdown preferred) or use `/ingest` with a URL
- `/ingest` reads the source, discusses key takeaways, then creates a **Source Summary** in `work/active/` with tag `source-summary`
- The summary uses the Source Summary template: Key Takeaways, Summary, Connections, Quotes/Data Points
- Every ingest updates `work/Index.md` (Sources section) and checks for cross-links to existing notes
- If the source contains decisions or patterns, update the relevant `brain/` notes too
- Source summaries link back to the raw source via the `source` frontmatter field

## Operation Log

Append to `log.md` after significant operations: ingests, decisions, project archives, maintenance passes.

- Format: `## [YYYY-MM-DD] <type> | <title>` followed by bullet points
- Types: `ingest`, `session`, `query`, `maintenance`, `decision`, `archive`
- Don't log every small edit — only operations that change the vault's knowledge state
- Entries are append-only; never edit or delete previous entries

## Query Writeback

When answering a substantial question that synthesizes multiple vault notes:

1. Offer: "This answer could be useful later — want me to save it as a reference note?"
2. If yes, create a Reference Note in `reference/` using the template
3. Link the reference note from related work notes in `## Related`
4. Add the reference note to `work/Index.md` under `## Reference`
5. Don't prompt for trivial questions — only for answers that synthesize, compare, or analyze

## Vault Location

The vault may live at the project root or in a `vault/` subdirectory. Use the SessionStart context to determine the actual path. All folder references above (e.g. `brain/`, `work/active/`) are relative to the vault root.

## Rules

- Preserve existing frontmatter when editing notes
- Always check for and suggest connections between notes
- Every note must have a `description` field (~150 chars)
- When reorganizing, never delete without user confirmation
- Use `[[wikilinks]]` not markdown links
