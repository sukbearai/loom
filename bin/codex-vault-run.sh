#!/bin/bash
# Codex-Vault wrapper — shows vault banner then launches Codex CLI
# Usage: codex-vault-run [codex args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"

# Find session-start hook relative to project or plugin
HOOK=""
for candidate in \
  "$PROJECT_DIR/plugin/hooks/codex/session-start.py" \
  "$PROJECT_DIR/.codex-vault/hooks/codex/session-start.py" \
  "$SCRIPT_DIR/../plugin/hooks/codex/session-start.py"; do
  if [ -f "$candidate" ]; then
    HOOK="$candidate"
    break
  fi
done

if [ -n "$HOOK" ]; then
  SUMMARY=$(echo '{}' | python3 "$HOOK" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('systemMessage',''))" 2>/dev/null)
  if [ -n "$SUMMARY" ]; then
    echo "  $SUMMARY"
  fi
fi

exec codex "$@"
