#!/usr/bin/env bash
# commit-msg hook: fail on AI attribution in the commit message. Same patterns as the
# check in .github/workflows/commits.yml; keep the two in sync.
set -euo pipefail

message_file="${1:?usage: no-ai-attribution.sh <commit message file>}"

# Comment lines are stripped by git before the commit is recorded, so they are ignored.
offending="$(grep -v '^#' "${message_file}" | grep -Ei \
  -e '^co-authored-by:.*(claude|anthropic|copilot|chatgpt|openai|codex|gemini)' \
  -e 'generated (with|by) .*(claude|copilot|chatgpt|codex|gemini)' || true)"

if [[ -n "${offending}" ]]; then
  echo "AI attribution is not allowed in commit messages:" >&2
  printf '  %s\n' "${offending}" >&2
  exit 1
fi
