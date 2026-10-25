#!/usr/bin/env bash
# Fails when a workflow or composite action pipes a producer into a consumer that can exit
# before reading all of its input (head, grep -q, grep -m, grep -l). Every run: block executes
# under "set -o pipefail", so the producer dies of SIGPIPE (exit 141) whenever it is still
# writing when the consumer leaves: an intermittent, timing-dependent failure.
# Usage: scripts/check-pipes.sh [FILE ...]   (default: .github/workflows/*.yml actions/*/action.yml)
set -euo pipefail

usage() {
  sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

main() {
  local -a files
  case "${1:-}" in
    -h | --help) usage 0 ;;
  esac
  if [[ "$#" -gt 0 ]]; then
    files=("$@")
  else
    shopt -s nullglob
    files=(.github/workflows/*.yml .github/workflows/*.yaml actions/*/action.yml actions/*/action.yaml)
  fi
  [[ "${#files[@]}" -gt 0 ]] || { echo "No files to check" >&2; exit 2; }

  # A pipe followed by head, or by grep with an option that stops at the first match.
  # Comment lines are skipped so the rule can be explained next to the code it protects.
  local pattern='\|[[:space:]]*(head\b|grep[[:space:]]([^|]*[[:space:]])?-([a-zA-Z]*[qlm]|-quiet|-silent|-max-count|-files-with-matches))'
  local hits
  hits="$(grep -nHE "${pattern}" "${files[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  if [[ -n "${hits}" ]]; then
    echo "Early-closing pipe consumer under pipefail (SIGPIPE, exit 141). Write the producer's" >&2
    echo "output to a file or a variable first, or use a consumer that reads all input:" >&2
    echo "${hits}" >&2
    exit 1
  fi
  echo "ok   no early-closing pipe consumer in ${#files[@]} files"
}

main "$@"
