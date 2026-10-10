#!/usr/bin/env bash
# Create a new project from repo-template and put it under the standards.
#
#   scripts/new-repo.sh <name> [--public|--private] [--description "text"] [--no-clone]
#   make new-repo NAME=<name>
#
# 1. creates <owner>/<name> from <owner>/repo-template with `gh repo create --template`
#    (asks public or private unless a flag says it) and clones it into the current directory;
# 2. opens a pull request in github-standards adding the repository to the projects map of
#    terraform/projects.tf. The next reviewed `tofu apply` imports it and applies the
#    standard settings and rulesets (terraform/README.md). Nothing is applied here.
#
# Uses the GitHub CLI session (`gh auth login`); never reads or prints a token.
set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

name=""
visibility=""
description=""
clone=1
while (($#)); do
  case "$1" in
    --public) visibility=public; shift ;;
    --private) visibility=private; shift ;;
    --description) description="${2:?--description needs a value}"; shift 2 ;;
    --no-clone) clone=0; shift ;;
    -h | --help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 2 ;;
    *) [[ -z "${name}" ]] || { echo "Only one repository name" >&2; usage 2; }; name="$1"; shift ;;
  esac
done

[[ -n "${name}" ]] || { echo "Missing the repository name" >&2; usage 2; }
[[ "${name}" =~ ^[A-Za-z0-9._-]{1,100}$ && "${name}" != .* ]] || {
  echo "Invalid repository name: ${name}" >&2
  exit 2
}
command -v gh > /dev/null || { echo "The GitHub CLI (gh) is required" >&2; exit 1; }
gh auth status > /dev/null 2>&1 || { echo "Not logged in: run gh auth login" >&2; exit 1; }

owner="${GITHUB_OWNER:-$(gh api user --jq .login)}"
template="${TEMPLATE_REPO:-${owner}/repo-template}"
standards="${STANDARDS_REPO:-${owner}/github-standards}"

if gh repo view "${owner}/${name}" > /dev/null 2>&1; then
  echo "${owner}/${name} already exists" >&2
  exit 1
fi
if [[ "$(gh api "repos/${template}" --jq .is_template)" != true ]]; then
  echo "${template} is not marked as a template repository (is_template = true in" >&2
  echo "terraform/repositories.tf, applied with tofu): gh cannot create from it yet." >&2
  exit 1
fi

if [[ -z "${visibility}" ]]; then
  [[ -r /dev/tty ]] || { echo "No terminal: pass --public or --private" >&2; exit 2; }
  while [[ "${visibility}" != public && "${visibility}" != private ]]; do
    printf 'Will %s be public or private? [private/public] ' "${owner}/${name}" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    case "${answer,,}" in
      "" | private | priv) visibility=private ;;
      public | pub) visibility=public ;;
      *) echo "Answer private or public." > /dev/tty ;;
    esac
  done
fi

# Private reusable workflows are callable only from private repositories of the same owner
# (README, section 3): a public project needs github-standards public too.
if [[ "${visibility}" == public ]] &&
  [[ "$(gh api "repos/${standards}" --jq .visibility)" != public ]]; then
  echo "Warning: ${standards} is private. The pr.yml and release.yml callers of a public" >&2
  echo "repository cannot use its reusable workflows until it is public (README, section 3)." >&2
  if [[ -r /dev/tty ]]; then
    printf 'Create %s as public anyway? [y/N] ' "${owner}/${name}" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    [[ "${answer,,}" == y || "${answer,,}" == yes ]] || exit 1
  else
    exit 1
  fi
fi

echo "==> Creating ${owner}/${name} (${visibility}) from ${template}"
create_args=("${owner}/${name}" --template "${template}" "--${visibility}")
[[ -z "${description}" ]] || create_args+=(--description "${description}")
if ((clone)); then create_args+=(--clone); fi
gh repo create "${create_args[@]}"

echo "==> Registering ${name} in ${standards} (terraform/projects.tf)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
gh repo clone "${standards}" "${work}/standards" -- --quiet --depth 1
cd "${work}/standards"

# HCL string: no double quote, backslash or newline, and template sequences escaped.
hcl_description="$(printf '%s' "${description}" | tr -d '"\\\r\n' | sed -e 's/[$]{/$${/g' -e 's/%{/%%{/g')"
marker='# new-repo.sh inserts entries above this line'
grep -q "${marker}" terraform/projects.tf || { echo "Marker not found in terraform/projects.tf" >&2; exit 1; }
# Multi-line entry: tofu fmt aligns consecutive one-line attributes, which would make the
# second added project fail the fmt check.
entry="$(printf '    "%s" = {\n      description = "%s"\n      visibility  = "%s"\n    }' \
  "${name}" "${hcl_description}" "${visibility}")"
ENTRY="${entry}" MARKER="${marker}" awk '
    index($0, ENVIRON["MARKER"]) { print ENVIRON["ENTRY"] }
    { print }
  ' terraform/projects.tf > terraform/projects.tf.new
mv terraform/projects.tf.new terraform/projects.tf

branch="feat/manage-${name,,}"
title="feat(terraform): manage the ${name} repository"
git switch --quiet --create "${branch}"
git add terraform/projects.tf
git commit --quiet --message "${title}" --message "- add ${name} (${visibility}, created from repo-template) to the projects map; the next apply imports it and applies the standard settings and rulesets, enforcement disabled until its checks have reported once"
git push --quiet --set-upstream origin "${branch}"
gh pr create --repo "${standards}" --head "${branch}" --title "${title}" --body "$(
  cat << BODY
## Description

### Context

\`${owner}/${name}\` was created from \`repo-template\` by \`scripts/new-repo.sh\`.

### What Changed

- \`terraform/projects.tf\`: \`${name}\` (${visibility}) added to the projects map, with the
  template's required checks and the rulesets disabled (adoption order, README section 9).

### How It Was Tested

- \`self-ci\` runs the mocked \`tofu test\`.

### Rollback Plan

Revert this pull request before the apply. After the apply, \`prevent_destroy\` keeps the
repository: remove it from state with \`tofu state rm\` instead.

### Security Notes

None. If the GitHub token for tofu is limited to selected repositories, add \`${name}\` to
it before the plan.

### Checklist

- [ ] \`tofu plan\` reviewed: one import, settings and two rulesets, nothing destroyed
- [ ] After the first pull request of \`${name}\`: switch its \`enforcement\` to \`active\`
BODY
)"

echo
echo "Done. Next: review and merge the github-standards pull request, then"
echo "tofu plan / tofu apply in terraform/ (terraform/README.md)."
if ((clone)); then echo "Your clone: ./${name}"; fi
