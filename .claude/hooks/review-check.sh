#!/usr/bin/env bash
# Review phase enforcement — reminds about review before pushing
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

if [[ "$COMMAND" != *"git push"* ]]; then exit 0; fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -z "$BRANCH" || "$BRANCH" == "main" ]]; then exit 0; fi

AHEAD=$(git rev-list --count main.."$BRANCH" 2>/dev/null || echo "0")
if [[ "$AHEAD" -gt 0 ]]; then
  echo "Pre-push reminder: $AHEAD commit(s) ahead of main. Ensure review agents were called."
fi

exit 0
