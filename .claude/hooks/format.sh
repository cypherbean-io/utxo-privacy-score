#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write)
# Formats the file that was just edited, if a formatter is configured.
# Must never block: always exit 0, including when no JSON parser is available.
set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
elif command -v python3 >/dev/null 2>&1; then
  FILE=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
p = d.get("tool_input", {}).get("file_path")
print(p if isinstance(p, str) else "")')
else
  exit 0
fi

{ [ -z "$FILE" ] || [ ! -f "$FILE" ]; } && exit 0

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md|*.yaml|*.yml)
    if [ -x node_modules/.bin/prettier ]; then
      node_modules/.bin/prettier --write "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
  *.py)
    command -v ruff >/dev/null 2>&1 && ruff format "$FILE" >/dev/null 2>&1 || true
    ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$FILE" >/dev/null 2>&1 || true
    ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$FILE" >/dev/null 2>&1 || true
    ;;
esac

exit 0
