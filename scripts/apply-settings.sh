#!/usr/bin/env bash
# Apply the standard settings and rulesets (README section 5) to one repository through the
# GitHub API. Idempotent: rulesets are updated in place by name. Same values as
# terraform/modules/repository; keep the two in sync. Terraform adopts the result later.
#
#   scripts/apply-settings.sh <owner>/<repository> [--checks "a,b,c"] [--enforcement active|disabled]
#                             [--wiki]
#
# --checks: required status checks (comma-separated); default: the repo-template pr.yml checks.
# --wiki: keep the wiki enabled (off by default: documentation lives in the repository).
# Prints `main_ruleset_id=<id>` and `tags_ruleset_id=<id>` on the last two lines.
# Uses the GitHub CLI session; never reads or prints a token.
set -euo pipefail

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

repo=""
checks="commits / conventional commits,security / gitleaks,security / zizmor"
enforcement=active
has_wiki=false
while (($#)); do
  case "$1" in
    --checks) checks="${2?--checks needs a value}"; shift 2 ;;
    --enforcement) enforcement="${2:?--enforcement needs a value}"; shift 2 ;;
    --wiki) has_wiki=true; shift ;;
    -h | --help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 2 ;;
    *) repo="$1"; shift ;;
  esac
done
[[ "${repo}" == */* ]] || { echo "Missing <owner>/<repository>" >&2; usage 2; }
[[ "${enforcement}" == active || "${enforcement}" == disabled ]] || usage 2

visibility="$(gh api "repos/${repo}" --jq .visibility)"
log() { printf '  %s\n' "$*" >&2; }
echo "==> Applying the standard settings to ${repo} (${visibility})" >&2

# Squash only: the PR title becomes the commit on main and drives the version bump.
gh api --silent --method PATCH "repos/${repo}" --input - << JSON
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY",
  "delete_branch_on_merge": true,
  "allow_auto_merge": true,
  "allow_update_branch": true,
  "has_wiki": ${has_wiki},
  "has_projects": false
}
JSON
log "merge settings: squash only, PR title and body, delete branch, auto-merge (wiki: ${has_wiki})"

gh api --silent --method PUT "repos/${repo}/vulnerability-alerts"
gh api --silent --method PUT "repos/${repo}/automated-security-fixes"
log "Dependabot alerts and security updates: on (version updates are Renovate's)"

gh api --silent --method PUT "repos/${repo}/actions/permissions" \
  -F enabled=true -f allowed_actions=all
log "Actions: enabled"

# Secret scanning and private vulnerability reporting are free on public repositories only
# (private ones need GitHub Code Security, which Pro does not include).
if [[ "${visibility}" == public ]]; then
  gh api --silent --method PATCH "repos/${repo}" --input - << 'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON
  gh api --silent --method PUT "repos/${repo}/private-vulnerability-reporting"
  log "secret scanning, push protection, private vulnerability reporting: on"
fi

# Create the ruleset, or update the one with the same name; prints its id.
upsert_ruleset() {
  local name="$1" body="$2" id
  id="$(gh api "repos/${repo}/rulesets" --jq ".[] | select(.name == \"${name}\") | .id")"
  if [[ -n "${id}" ]]; then
    gh api --silent --method PUT "repos/${repo}/rulesets/${id}" --input - <<< "${body}"
  else
    id="$(gh api --method POST "repos/${repo}/rulesets" --input - --jq .id <<< "${body}")"
  fi
  echo "${id}"
}

main_body="$(CHECKS="${checks}" ENFORCEMENT="${enforcement}" python3 -c '
import json, os
checks = [c.strip() for c in os.environ["CHECKS"].split(",") if c.strip()]
rules = [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "required_signatures"},
    {"type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": True,
        "require_code_owner_review": False,
        "require_last_push_approval": False,
        "required_review_thread_resolution": True,
        "allowed_merge_methods": ["squash"],
    }},
]
if checks:
    rules.append({"type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": True,
        "do_not_enforce_on_create": False,
        "required_status_checks": [{"context": c} for c in checks],
    }})
print(json.dumps({
    "name": "main-protection", "target": "branch", "enforcement": os.environ["ENFORCEMENT"],
    "bypass_actors": [],
    "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
    "rules": rules,
}))
')"
tags_body="$(ENFORCEMENT="${enforcement}" python3 -c '
import json, os
print(json.dumps({
    "name": "release-tags", "target": "tag", "enforcement": os.environ["ENFORCEMENT"],
    "bypass_actors": [],
    "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
    "rules": [{"type": "deletion"}, {"type": "update"}, {"type": "non_fast_forward"}],
}))
')"

main_id="$(upsert_ruleset main-protection "${main_body}")"
tags_id="$(upsert_ruleset release-tags "${tags_body}")"
log "rulesets main-protection (${main_id}) and release-tags (${tags_id}): ${enforcement}"
log "required checks: ${checks:-none}"

echo "main_ruleset_id=${main_id}"
echo "tags_ruleset_id=${tags_id}"
