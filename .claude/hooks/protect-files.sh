#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write|NotebookEdit)
# Blocks edits to sensitive or agent-configuration paths.
# Exit 2 = block; the stderr message is fed back to Claude as feedback.
#
# FAILS CLOSED: if neither jq nor python3 is on PATH, this blocks rather than
# silently allowing everything.
set -uo pipefail

INPUT=$(cat)

extract() {   # $1 = dotted path, e.g. tool_input.file_path
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".$1 // empty"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); sys.exit(0)
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(d if isinstance(d, str) else "")' "$1"
  else
    return 1
  fi
}

if ! FILE_PATH=$(extract tool_input.file_path); then
  echo "Blocked: this repository's protect-files hook needs 'jq' or 'python3' on PATH to inspect tool input and found neither. Install one, or remove the hook from .claude/settings.json." >&2
  exit 2
fi
[ -z "$FILE_PATH" ] && FILE_PATH=$(extract tool_input.notebook_path)
[ -z "$FILE_PATH" ] && exit 0

# Normalize Windows separators so the patterns below match.
FILE_PATH="${FILE_PATH//\\//}"

PROTECTED=(
  ".env"
  "secrets/"
  ".git/"
  ".github/workflows/"
  ".claude/settings.json"
  ".claude/hooks/"
  ".claude/scaffold-manifest"
  ".mcp.json"
  "id_rsa"
  ".pem"
  ".p12"
  ".keystore"
  "package-lock.json"
  "pnpm-lock.yaml"
  "yarn.lock"
  "Cargo.lock"
  "poetry.lock"
  "go.sum"
)

for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: '$FILE_PATH' matches protected pattern '$pattern'. Ask the user to make this change, or explain why it is required and let them do it." >&2
    exit 2
  fi
done

exit 0
