# Sources

Drop raw source files here — articles, papers, web clips saved as markdown.

## How It Works

- The LLM agent **reads** from this directory but **never modifies** source files.
- Sources are immutable reference material. The agent creates summaries in `work/active/` instead.
- Use `/ingest` (Claude Code) or say "ingest this source" (Codex CLI) to process a new source into a wiki page with cross-links.

## Supported Formats

- Markdown files (`.md`) — preferred
- Plain text (`.txt`)
- Web clips saved via `defuddle parse <url> --md > sources/filename.md`

## Naming

Use descriptive filenames: `karpathy-llm-wiki.md`, `react-server-components-rfc.md`, etc.
