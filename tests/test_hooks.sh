#!/bin/bash
set -eo pipefail

# Hook-only test suite — tests both Claude and Codex hook scripts
# Run: npm run test:hooks  or  bash tests/test_hooks.sh

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); ERRORS+=("$1: $2"); echo -e "  ${RED}FAIL${NC} $1 — $2"; }
configure_git_user() {
  git config user.email "codex-vault-tests@example.com"
  git config user.name "Codex Vault Tests"
}

# Setup temp vault
TEST_DIR=$(mktemp -d)
cp -r "$REPO_DIR"/{plugin,vault} "$TEST_DIR/"
cd "$TEST_DIR/vault"
git init -q && configure_git_user && git add -A && git commit -q -m "init"

echo "=== Hook Tests ==="
echo "Test dir: $TEST_DIR"
echo ""

# ============================================================
echo "--- 1. Claude session-start ---"
# ============================================================

OUT=$(CLAUDE_PROJECT_DIR="$TEST_DIR/vault" python3 "$TEST_DIR/plugin/hooks/claude/session-start.py" < /dev/null 2>/dev/null)

# Valid JSON
if echo "$OUT" | python3 -m json.tool > /dev/null 2>&1; then
  pass "claude/session-start: valid JSON output"
else
  fail "claude/session-start: JSON" "invalid JSON"
fi

# Has systemMessage
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('systemMessage')" 2>/dev/null; then
  pass "claude/session-start: has systemMessage"
else
  fail "claude/session-start: systemMessage" "missing"
fi

# Has hookSpecificOutput
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['additionalContext']" 2>/dev/null; then
  pass "claude/session-start: has additionalContext"
else
  fail "claude/session-start: additionalContext" "missing"
fi

# Context has required sections
for section in "### Date" "### North Star" "### Recent Changes" "### Active Work" "### Vault Files"; do
  if echo "$OUT" | grep -q "$section"; then
    pass "claude/session-start: $section"
  else
    fail "claude/session-start: $section" "missing"
  fi
done

echo ""

# ============================================================
echo "--- 2. Codex session-start ---"
# ============================================================

OUT=$(echo '{}' | python3 "$TEST_DIR/plugin/hooks/codex/session-start.py" 2>/dev/null)

# Valid JSON
if echo "$OUT" | python3 -m json.tool > /dev/null 2>&1; then
  pass "codex/session-start: valid JSON output"
else
  fail "codex/session-start: JSON" "invalid JSON"
fi

# Uses hookSpecificOutput (not systemMessage for context)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName'] == 'SessionStart'" 2>/dev/null; then
  pass "codex/session-start: hookEventName=SessionStart"
else
  fail "codex/session-start: hookEventName" "wrong or missing"
fi

if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['hookSpecificOutput']['additionalContext']) > 100" 2>/dev/null; then
  pass "codex/session-start: additionalContext has content"
else
  fail "codex/session-start: additionalContext" "empty or too short"
fi

# Has systemMessage summary
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '[Vault]' in d.get('systemMessage','')" 2>/dev/null; then
  pass "codex/session-start: systemMessage has [Vault] summary"
else
  fail "codex/session-start: systemMessage" "missing [Vault] summary"
fi

# Misregistered tool event — no invalid additionalContext
OUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/session-start.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/session-start: ignores non-SessionStart event"
else
  fail "codex/session-start: wrong event" "unexpected: $OUT"
fi

echo ""

# ============================================================
echo "--- 3. Claude classify-message ---"
# ============================================================

# Signal detection
for pair in "decided:DECISION" "kudos:WIN" "sprint milestone:PROJECT UPDATE" "how does:QUERY" "ingest this:INGEST"; do
  prompt="${pair%%:*}"
  signal="${pair##*:}"
  OUT=$(echo "{\"prompt\":\"$prompt\"}" | python3 "$TEST_DIR/plugin/hooks/claude/classify-message.py" 2>/dev/null)
  if echo "$OUT" | grep -q "$signal"; then
    pass "claude/classify: '$prompt' → $signal"
  else
    fail "claude/classify: $signal" "not triggered by '$prompt'"
  fi
done

# No false positive
OUT=$(echo '{"prompt":"fix the typo"}' | python3 "$TEST_DIR/plugin/hooks/claude/classify-message.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "claude/classify: no false positive"
else
  fail "claude/classify: false positive" "triggered on 'fix the typo'"
fi

# Session end
OUT=$(echo '{"prompt":"wrap up"}' | python3 "$TEST_DIR/plugin/hooks/claude/classify-message.py" 2>/dev/null)
if echo "$OUT" | grep -q "SESSION END"; then
  pass "claude/classify: session end detected"
else
  fail "claude/classify: session end" "not detected"
fi

# Graceful error handling
echo 'bad json' | python3 "$TEST_DIR/plugin/hooks/claude/classify-message.py" > /dev/null 2>&1; RC=$?
if [ $RC -eq 0 ]; then
  pass "claude/classify: handles bad JSON"
else
  fail "claude/classify: bad JSON" "exit $RC"
fi

echo "" | python3 "$TEST_DIR/plugin/hooks/claude/classify-message.py" > /dev/null 2>&1; RC=$?
if [ $RC -eq 0 ]; then
  pass "claude/classify: handles empty input"
else
  fail "claude/classify: empty input" "exit $RC"
fi

echo ""

# ============================================================
echo "--- 4. Codex classify-message ---"
# ============================================================

# Uses hookSpecificOutput format
OUT=$(echo '{"prompt":"we decided to use Redis"}' | python3 "$TEST_DIR/plugin/hooks/codex/classify-message.py" 2>/dev/null)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName'] == 'UserPromptSubmit'" 2>/dev/null; then
  pass "codex/classify: hookEventName=UserPromptSubmit"
else
  fail "codex/classify: hookEventName" "wrong or missing"
fi

if echo "$OUT" | grep -q "DECISION"; then
  pass "codex/classify: DECISION signal works"
else
  fail "codex/classify: DECISION" "not triggered"
fi

# No false positive
OUT=$(echo '{"prompt":"fix typo"}' | python3 "$TEST_DIR/plugin/hooks/codex/classify-message.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/classify: no false positive"
else
  fail "codex/classify: false positive" "triggered on 'fix typo'"
fi

# Misregistered tool event — no invalid additionalContext
OUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Read","prompt":"we decided to use Redis"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/classify-message.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/classify: ignores non-UserPromptSubmit event"
else
  fail "codex/classify: wrong event" "unexpected: $OUT"
fi

echo ""

# ============================================================
echo "--- 5. Claude validate-write ---"
# ============================================================

# Valid note — silent
GOOD="$TEST_DIR/vault/work/active/Good.md"
mkdir -p "$TEST_DIR/vault/work/active"
cat > "$GOOD" << 'EOF'
---
date: "2026-04-07"
description: "Good note"
tags: [meta]
---
# Good
Content with [[wikilinks]].
EOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$GOOD\"}}" | python3 "$TEST_DIR/plugin/hooks/claude/validate-write.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "claude/validate: valid note passes"
else
  fail "claude/validate: valid note" "unexpected: $OUT"
fi

# Bad note — warnings
BAD="$TEST_DIR/vault/work/active/Bad.md"
cat > "$BAD" << 'BADEOF'
No frontmatter here. No wikilinks either. Padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding.
BADEOF

OUT=$(echo "{\"tool_input\":{\"file_path\":\"$BAD\"}}" | python3 "$TEST_DIR/plugin/hooks/claude/validate-write.py" 2>/dev/null)
if echo "$OUT" | grep -q "Missing YAML frontmatter"; then
  pass "claude/validate: detects missing frontmatter"
else
  fail "claude/validate: frontmatter" "not detected"
fi
if echo "$OUT" | grep -q "wikilinks"; then
  pass "claude/validate: detects missing wikilinks"
else
  fail "claude/validate: wikilinks" "not detected"
fi

# Skip non-vault files
OUT=$(echo '{"tool_input":{"file_path":"README.md"}}' | python3 "$TEST_DIR/plugin/hooks/claude/validate-write.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "claude/validate: skips README.md"
else
  fail "claude/validate: skip" "should skip README.md"
fi

rm -f "$GOOD" "$BAD"

echo ""

# ============================================================
echo "--- 6. Codex validate-write (Bash PostToolUse) ---"
# ============================================================

# Hard failure detection
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":"{\"exit_code\":1,\"stdout\":\"npm ERR! command not found: node\",\"stderr\":\"\"}"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['decision'] == 'block'" 2>/dev/null; then
  pass "codex/validate: hard failure → block"
else
  fail "codex/validate: hard failure" "not blocked"
fi

if echo "$OUT" | grep -q "additionalContext"; then
  fail "codex/validate: hard failure output" "contains unsupported additionalContext"
else
  pass "codex/validate: hard failure output has no additionalContext"
fi

# Permission denied
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"rm /etc/hosts"},"tool_response":"rm: /etc/hosts: Permission denied"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if echo "$OUT" | grep -q "block"; then
  pass "codex/validate: permission denied → block"
else
  fail "codex/validate: permission denied" "not blocked"
fi

# Non-zero exit code with output
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"pytest"},"tool_response":"{\"exit_code\":1,\"stdout\":\"2 failed, 5 passed\",\"stderr\":\"\"}"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if echo "$OUT" | grep -q "block"; then
  pass "codex/validate: non-zero exit → block for review"
else
  fail "codex/validate: non-zero exit" "not blocked"
fi

# Success — no output
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"{\"exit_code\":0,\"stdout\":\"file.txt\",\"stderr\":\"\"}"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/validate: success → silent"
else
  fail "codex/validate: success" "unexpected: $OUT"
fi

# Non-Bash tool — ignored
OUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"foo.md"},"tool_response":"ok"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/validate: non-Bash tool ignored"
else
  fail "codex/validate: non-Bash" "should be silent"
fi

# Misregistered PreToolUse event — no invalid additionalContext or block
OUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":"{\"exit_code\":1,\"stdout\":\"npm ERR! command not found: node\",\"stderr\":\"\"}"}' \
  | python3 "$TEST_DIR/plugin/hooks/codex/validate-write.py" 2>/dev/null)
if [ -z "$OUT" ]; then
  pass "codex/validate: ignores non-PostToolUse event"
else
  fail "codex/validate: wrong event" "unexpected: $OUT"
fi

echo ""

# ============================================================
# Summary
# ============================================================

rm -rf "$TEST_DIR"

echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
echo -e "${RED}FAIL: $FAIL${NC}"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
fi

echo ""
[ $FAIL -eq 0 ] && echo -e "${GREEN}All hook tests passed.${NC}" && exit 0
echo -e "${RED}$FAIL test(s) failed.${NC}" && exit 1
