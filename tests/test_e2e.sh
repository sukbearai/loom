#!/bin/bash
set -eo pipefail

# Loom End-to-End Test Suite
# Simulates a real user: install → session-start → classify → validate → full cycle
# Run from repo root: bash tests/test_e2e.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
ERRORS=()

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); ERRORS+=("$1: $2"); echo -e "  ${RED}FAIL${NC} $1 — $2"; }

echo "=== Loom E2E Tests ==="
echo "Repo:     $REPO_DIR"
echo "Test dir: $TEST_DIR"
echo ""

# ============================================================
echo "--- 1. Install ---"
# ============================================================

# Copy repo to test dir (simulate git clone)
cp -r "$REPO_DIR"/{plugin,adapters,vault,docs,README.md,LICENSE,.gitignore} "$TEST_DIR/"
cd "$TEST_DIR"
git init -q && git add -A && git commit -q -m "init"

# Run installer
OUTPUT=$(bash plugin/install.sh 2>&1)

# Check Claude Code config generated
if [ -f "vault/.claude/settings.json" ]; then
  pass "Claude Code settings.json generated"
else
  fail "Claude Code settings.json" "file not found"
fi

# Check Codex CLI config generated (only if codex is installed)
if command -v codex &>/dev/null; then
  if [ -f "vault/.codex/hooks.json" ]; then
    pass "Codex CLI hooks.json generated"
  else
    fail "Codex CLI hooks.json" "file not found"
  fi
else
  echo -e "  ${YELLOW}SKIP${NC} Codex CLI hooks.json (codex not installed)"
fi

# Check CLAUDE.md generated
if [ -f "vault/CLAUDE.md" ]; then
  pass "CLAUDE.md generated"
  LINES=$(wc -l < vault/CLAUDE.md | tr -d ' ')
  if [ "$LINES" -gt 50 ]; then
    pass "CLAUDE.md has content ($LINES lines)"
  else
    fail "CLAUDE.md content" "only $LINES lines"
  fi
else
  fail "CLAUDE.md" "file not found"
fi

# Check commands copied
for cmd in standup dump wrap-up ingest; do
  if [ -f "vault/.claude/commands/$cmd.md" ]; then
    pass "Command /$cmd installed"
  else
    fail "Command /$cmd" "not found in vault/.claude/commands/"
  fi
done

# Check settings.json is valid JSON
if python3 -m json.tool vault/.claude/settings.json > /dev/null 2>&1; then
  pass "settings.json is valid JSON"
else
  fail "settings.json" "invalid JSON"
fi

echo ""

# ============================================================
echo "--- 2. SessionStart Hook ---"
# ============================================================

cd "$TEST_DIR/vault"

# Export vars that session-start.sh expects
export CLAUDE_PROJECT_DIR="$TEST_DIR/vault"

OUTPUT=$(bash ../plugin/hooks/session-start.sh 2>&1)

# Check sections exist
for section in "### Date" "### North Star" "### Recent Changes" "### Recent Operations" "### Active Work" "### Vault Files"; do
  if echo "$OUTPUT" | grep -q "$section"; then
    pass "session-start: $section present"
  else
    fail "session-start: $section" "section missing from output"
  fi
done

# Check North Star content injected
if echo "$OUTPUT" | grep -q "living document"; then
  pass "session-start: North Star content injected"
else
  fail "session-start: North Star" "content not found"
fi

# Check log.md entries shown
if echo "$OUTPUT" | grep -q "Initial vault setup"; then
  pass "session-start: log.md entries shown"
else
  fail "session-start: log.md" "entries not found"
fi

# Check vault files listed
if echo "$OUTPUT" | grep -q "Home.md"; then
  pass "session-start: vault files listed"
else
  fail "session-start: vault files" "Home.md not in listing"
fi

echo ""

# ============================================================
echo "--- 3. Classify Message Hook ---"
# ============================================================

cd "$TEST_DIR"

# Test DECISION signal
OUT=$(echo '{"prompt":"we decided to use PostgreSQL"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "DECISION"; then
  pass "classify: DECISION signal triggers"
else
  fail "classify: DECISION" "signal not triggered"
fi

# Test WIN signal
OUT=$(echo '{"prompt":"we shipped the new feature"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "WIN"; then
  pass "classify: WIN signal triggers"
else
  fail "classify: WIN" "signal not triggered"
fi

# Test PROJECT UPDATE signal
OUT=$(echo '{"prompt":"sprint milestone reached"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "PROJECT UPDATE"; then
  pass "classify: PROJECT UPDATE signal triggers"
else
  fail "classify: PROJECT UPDATE" "signal not triggered"
fi

# Test QUERY signal
OUT=$(echo '{"prompt":"how does the auth system work?"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "QUERY"; then
  pass "classify: QUERY signal triggers"
else
  fail "classify: QUERY" "signal not triggered"
fi

# Test INGEST signal
OUT=$(echo '{"prompt":"ingest this article about databases"}' | python3 plugin/hooks/classify-message.py)
if echo "$OUT" | grep -q "INGEST"; then
  pass "classify: INGEST signal triggers"
else
  fail "classify: INGEST" "signal not triggered"
fi

# Test no false positive on normal message
OUT=$(echo '{"prompt":"fix the typo in line 42"}' | python3 plugin/hooks/classify-message.py)
if [ -z "$OUT" ]; then
  pass "classify: no false positive on normal message"
else
  fail "classify: false positive" "triggered on 'fix the typo in line 42': $OUT"
fi

# Test empty/malformed input
OUT=$(echo '{}' | python3 plugin/hooks/classify-message.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "classify: handles empty input gracefully"
else
  fail "classify: empty input" "exit code $RC"
fi

OUT=$(echo 'not json' | python3 plugin/hooks/classify-message.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "classify: handles malformed JSON gracefully"
else
  fail "classify: malformed JSON" "exit code $RC"
fi

echo ""

# ============================================================
echo "--- 4. Validate Write Hook ---"
# ============================================================

cd "$TEST_DIR"

# Test: valid vault note (should pass silently)
VALID_NOTE="$TEST_DIR/vault/work/active/Test Project.md"
mkdir -p "$TEST_DIR/vault/work/active"
cat > "$VALID_NOTE" << 'EOF'
---
date: "2026-04-06"
description: "Test project for E2E validation"
status: active
tags:
  - work-note
---

# Test Project

## Context

Testing the [[Loom]] vault system.

## Related

- [[Key Decisions]]
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$VALID_NOTE\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: valid note passes silently"
else
  fail "validate: valid note" "unexpected warnings: $OUT"
fi

# Test: note missing frontmatter
BAD_NOTE="$TEST_DIR/vault/work/active/Bad Note.md"
cat > "$BAD_NOTE" << 'EOF'
# No Frontmatter

This note has no YAML frontmatter and no wikilinks. It should trigger warnings.
It needs to be longer than 300 chars to trigger the wikilink check.
Here is some padding text to make it long enough for the validator to check.
More padding here to ensure we cross the 300 character threshold easily.
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$BAD_NOTE\"}}" | python3 plugin/hooks/validate-write.py)
if echo "$OUT" | grep -q "Missing YAML frontmatter"; then
  pass "validate: detects missing frontmatter"
else
  fail "validate: missing frontmatter" "warning not generated"
fi
if echo "$OUT" | grep -q "wikilinks"; then
  pass "validate: detects missing wikilinks"
else
  fail "validate: missing wikilinks" "warning not generated"
fi

# Test: skips non-vault files
OUT=$(echo "{\"tool_input\":{\"file_path\":\"$TEST_DIR/vault/README.md\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: skips README.md"
else
  fail "validate: skip README" "should have been skipped"
fi

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$TEST_DIR/vault/templates/Work Note.md\"}}" | python3 plugin/hooks/validate-write.py)
if [ -z "$OUT" ]; then
  pass "validate: skips templates/"
else
  fail "validate: skip templates" "should have been skipped"
fi

# Test: handles missing file_path gracefully
OUT=$(echo '{"tool_input":{}}' | python3 plugin/hooks/validate-write.py 2>&1); RC=$?
if [ $RC -eq 0 ]; then
  pass "validate: handles missing file_path"
else
  fail "validate: missing file_path" "exit code $RC"
fi

echo ""

# ============================================================
echo "--- 5. Vault Structure Integrity ---"
# ============================================================

cd "$TEST_DIR/vault"

# Check all expected files exist
for f in Home.md log.md brain/North\ Star.md brain/Memories.md brain/Key\ Decisions.md brain/Patterns.md work/Index.md; do
  if [ -f "$f" ]; then
    pass "vault: $f exists"
  else
    fail "vault: $f" "file missing"
  fi
done

# Check all expected directories exist
for d in brain work/active work/archive templates thinking sources reference; do
  if [ -d "$d" ]; then
    pass "vault: $d/ exists"
  else
    fail "vault: $d/" "directory missing"
  fi
done

# Check frontmatter on vault notes
for f in Home.md brain/North\ Star.md brain/Memories.md brain/Key\ Decisions.md brain/Patterns.md work/Index.md log.md; do
  if head -1 "$f" | grep -q "^---"; then
    pass "vault: $f has frontmatter"
  else
    fail "vault: $f frontmatter" "missing YAML frontmatter"
  fi
done

# Check wikilinks exist in key files
for f in Home.md brain/Memories.md; do
  if grep -q "\[\[" "$f"; then
    pass "vault: $f has wikilinks"
  else
    fail "vault: $f wikilinks" "no [[wikilinks]] found"
  fi
done

# Check templates have placeholders
for f in templates/*.md; do
  if grep -q "{{" "$f"; then
    pass "vault: $(basename "$f") has placeholders"
  else
    fail "vault: $(basename "$f")" "no {{placeholders}} found"
  fi
done

echo ""

# ============================================================
echo "--- 6. Cross-File Consistency ---"
# ============================================================

# Check instructions.md mentions all directories that exist
INSTRUCTIONS="$TEST_DIR/plugin/instructions.md"
for dir in brain work sources reference thinking templates; do
  if grep -q "$dir" "$INSTRUCTIONS"; then
    pass "instructions.md: mentions $dir/"
  else
    fail "instructions.md: $dir/" "not mentioned"
  fi
done

# Check all 5 signals are in classify-message.py
CLASSIFY="$TEST_DIR/plugin/hooks/classify-message.py"
for signal in DECISION WIN "PROJECT UPDATE" QUERY INGEST; do
  if grep -q "\"$signal\"" "$CLASSIFY"; then
    pass "classify: signal $signal defined"
  else
    fail "classify: signal $signal" "not found in classify-message.py"
  fi
done

# Check README vault structure matches actual vault
README="$TEST_DIR/README.md"
for item in Home.md log.md brain work sources reference templates thinking; do
  if grep -q "$item" "$README"; then
    pass "README: mentions $item"
  else
    fail "README: $item" "not in vault structure section"
  fi
done

echo ""

# ============================================================
# Summary
# ============================================================

echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${RED}FAIL: $FAIL${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
  echo ""
fi

# Cleanup
rm -rf "$TEST_DIR"

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}All tests passed.${NC}"
  exit 0
else
  echo -e "${RED}$FAIL test(s) failed.${NC}"
  exit 1
fi
