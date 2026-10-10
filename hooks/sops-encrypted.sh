#!/usr/bin/env bash
# pre-commit hook: fail when a sops file is committed in clear text. An encrypted file
# carries the top-level sops metadata block with its MAC and ENC[...] values.
set -euo pipefail

status=0
for file in "$@"; do
  if ! grep -q '^sops:' "${file}" || ! grep -Eq '^[[:space:]]+mac: ENC\[' "${file}"; then
    echo "${file}: not encrypted with sops (run: sops --encrypt --in-place ${file})" >&2
    status=1
  fi
done
exit "${status}"
