---
date: "{{date}}"
description: "Vault schema — domain scope, naming rules, tag taxonomy"
tags: [meta]
---

# Schema

Vault structure and constraint definitions. The agent reads this file at the start of every session.

## Domain

<!-- User-defined: what domain does this vault focus on? -->
General knowledge management

## Naming Conventions

- Use descriptive titles as file names (e.g. "Key Decisions.md")
- Avoid special characters in paths
- Files under brain/ have fixed names — do not rename them

## Tag Taxonomy

<!-- All available tags are declared here. New tags must be added to this list first. -->

- brain — persistent memory files in brain/
- index — navigation and index pages
- meta — vault system files
- decision — decision records
- pattern — discovered regularities
- source-summary — source material summaries
- project — project-related notes
- reference — reference materials
- work-note — work notes and project logs
- thinking — drafts and temporary ideas

## Page Thresholds

- **Create a page**: topic appears in 2+ sources, or is a core topic of a single source
- **Update existing page**: when new information relates to an existing page, prefer updating over creating
- **Split a page**: when a page exceeds 200 lines, split by subtopic with mutual links
- **Archive a page**: when content is fully outdated, move to `work/archive/`

## Frontmatter Requirements

Every note must include:
- `date`: YYYY-MM-DD
- `description`: ~150 character description
- `tags`: list of tags from the Tag Taxonomy above
- `contradictions`: (optional) list of page names that contradict this page
- `type`: (optional) note type, allowed values:
  - work — work notes / projects
  - decision — decision records
  - source-summary — source material summaries
  - reference — synthesized reference notes
  - thinking — drafts / temporary ideas
- `sources`: (optional) list of vault paths to source documents, e.g. `[sources/article-name.md]`
