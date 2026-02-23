#!/usr/bin/env bash
# Documentation sync validation — checks that example changes include doc updates
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

if [[ "$COMMAND" != *"git commit"* && "$COMMAND" != *"gh pr create"* ]]; then exit 0; fi

STAGED=$(git diff --cached --name-only 2>/dev/null || echo "")
if [[ -z "$STAGED" ]]; then exit 0; fi

WARNINGS=""

# Check: examples/ changed -> examples dir CLAUDE.md should be updated
if echo "$STAGED" | grep -q "^examples/" \
   && ! echo "$STAGED" | grep -q "^examples/CLAUDE.md"; then
  WARNINGS="${WARNINGS}\n  - examples/ changed but examples/CLAUDE.md not updated"
fi

# Check: example TOML changed -> docs should be updated
if echo "$STAGED" | grep -qE "\.toml$" \
   && ! echo "$STAGED" | grep -q "^docs/"; then
  WARNINGS="${WARNINGS}\n  - TOML config changed but docs/ not updated"
fi

if [[ -n "$WARNINGS" ]]; then
  echo "Documentation check warnings:${WARNINGS}"
  echo ""
  echo "Review .claude/rules/documentation-maintenance.md"
  exit 0
fi

exit 0
