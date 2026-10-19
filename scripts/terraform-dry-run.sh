#!/usr/bin/env bash
# Dry run of terraform/ against the live repositories, with no state backend: a throwaway copy
# of the configuration with a local backend and import blocks for everything that already
# exists on GitHub, then `tofu plan`. Read-only API calls; nothing is applied, no state is
# kept, no bucket or cloud account is needed.
#
#   scripts/terraform-dry-run.sh [--keep]
#   make plan-dry-run
#
# Token: GITHUB_TOKEN when set (terraform/README.md, section 3), else the GitHub CLI session
# (`gh auth token`), acceptable here because a plan only reads. Never printed.
# --keep: keep the working copy (generated imports, plan file) and print its path.
# Needs tofu (the version of actions/setup-tools), gh and jq.
set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

keep=0
while (($#)); do
  case "$1" in
    --keep) keep=1; shift ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

for tool in tofu gh jq; do
  command -v "${tool}" > /dev/null || { echo "${tool} is required" >&2; exit 1; }
done
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  GITHUB_TOKEN="$(gh auth token)" || { echo "Not logged in: run gh auth login" >&2; exit 1; }
fi
export GITHUB_TOKEN

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
owner="${TF_VAR_github_owner:-xxarequipenoxx}"
work="$(mktemp -d)"
cleanup() { if ((keep)); then echo "Working copy kept: ${work}" >&2; else rm -rf "${work}"; fi; }
trap cleanup EXIT

# Configuration only: no provider cache, no state, no backend settings of a previous run.
cp -r "${root}/terraform/." "${work}/"
rm -rf "${work}/.terraform" "${work}/.terraform.lock.hcl" "${work}/backend.hcl" "${work}"/*.tfstate* "${work}"/*.tfplan

# An override file replaces the s3 backend of backend.tf with a local one in the copy.
cat > "${work}/zz_dry_run_override.tf" << 'HCL'
terraform {
  backend "local" {}
}
HCL

# Import blocks for what exists: the plan then shows the real diff, not a create. Imports in a
# plan are only previewed; nothing is written anywhere.
imports="${work}/zz_dry_run_imports.tf"
: > "${imports}"
import() { printf 'import {\n  to = %s\n  id = "%s"\n}\n\n' "$1" "$2" >> "${imports}"; }

repository_imports() { # <module address> <repository> <with rulesets: 0|1>
  local address="$1" repo="$2" rulesets="$3" visibility id
  if ! visibility="$(gh api "repos/${owner}/${repo}" --jq .visibility 2> /dev/null)"; then
    echo "  ${repo}: not on GitHub, the plan creates it" >&2
    return 0
  fi
  if ((rulesets)); then
    import "${address}.github_repository.this" "${repo}"
    for pair in main:main-protection release_tags:release-tags; do
      id="$(gh api "repos/${owner}/${repo}/rulesets" --jq ".[] | select(.name == \"${pair#*:}\") | .id")"
      [[ -z "${id}" ]] || import "${address}.github_repository_ruleset.${pair%%:*}" "${repo}:${id}"
    done
  fi
  import "${address}.github_repository_vulnerability_alerts.this" "${repo}"
  import "${address}.github_repository_dependabot_security_updates.this" "${repo}"
  [[ "${visibility}" == public ]] || import "${address}.github_actions_repository_access_level.this[0]" "${repo}"
}

echo "==> Reading the live repositories of ${owner}" >&2
# Module calls of repositories.tf: everything is imported here.
while read -r module repo; do
  repository_imports "module.${module}" "${repo}" 1
done < <(awk '/^module "/ { gsub(/"/, "", $2); m = $2 } m && /^  name +=/ { gsub(/"/, "", $3); print m, $3; m = "" }' "${work}/repositories.tf")
# Entries of projects.tf: the repository and its rulesets come from the import blocks there.
while read -r repo; do
  repository_imports "module.projects[\"${repo}\"]" "${repo}" 0
done < <(sed -n 's/^    "\([A-Za-z0-9._-]*\)" = {$/\1/p' "${work}/projects.tf")

cd "${work}"
echo "==> tofu init (local backend, throwaway)" >&2
tofu init -input=false -no-color > init.log || { cat init.log >&2; exit 1; }
echo "==> tofu plan (read-only)" >&2
tofu plan -input=false -lock=false -no-color -out=dry-run.tfplan

echo "==> Summary" >&2
tofu show -json dry-run.tfplan | jq -r '
  [.resource_changes[] | (if .change.importing then "import" else empty end), (.change.actions | join("+"))]
  | map(select(. != "no-op")) | group_by(.) | map("  \(.[0]): \(length)") | .[]' >&2
tofu show -json dry-run.tfplan | jq -r '
  .resource_changes[] | select(.change.actions | index("delete")) | "  DELETE \(.address)"' >&2
