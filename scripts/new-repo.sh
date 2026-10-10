#!/usr/bin/env bash
# Create a new project from the latest release of repo-template, fully under the standards.
#
#   scripts/new-repo.sh <name> [--public|--private] [--description "text"]
#                       [--template-ref vX.Y.Z] [--no-register]
#   make new-repo NAME=<name> [VISIBILITY=public|private]
#
# 1. asks public or private unless a flag says it;
# 2. creates <owner>/<name> and pushes the content of the latest repo-template release as
#    its first commit (the version is recorded in the commit message), cloned in ./<name>;
# 3. applies the standard settings and active rulesets right away (apply-settings.sh):
#    squash only, Dependabot alerts and security updates, secret scanning on public repos;
# 4. opens a pull request in github-standards adding the repository to
#    terraform/projects.tf, with import blocks so the next reviewed apply adopts it as is.
#
# Uses the GitHub CLI session (`gh auth login`, `gh auth setup-git`); never prints a token.
set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

name=""
visibility=""
description=""
template_ref=""
register=1
while (($#)); do
  case "$1" in
    --public) visibility=public; shift ;;
    --private) visibility=private; shift ;;
    --description) description="${2:?--description needs a value}"; shift 2 ;;
    --template-ref) template_ref="${2:?--template-ref needs a value}"; shift 2 ;;
    --no-register) register=0; shift ;;
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
[[ ! -e "${name}" ]] || { echo "./${name} already exists" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
owner="${GITHUB_OWNER:-$(gh api user --jq .login)}"
template="${TEMPLATE_REPO:-${owner}/repo-template}"
standards="${STANDARDS_REPO:-${owner}/github-standards}"

if gh repo view "${owner}/${name}" > /dev/null 2>&1; then
  echo "${owner}/${name} already exists" >&2
  exit 1
fi
if [[ -z "${template_ref}" ]]; then
  template_ref="$(gh release view --repo "${template}" --json tagName --jq .tagName 2> /dev/null || true)"
  [[ -n "${template_ref}" ]] || {
    echo "${template} has no release yet: merge a feat or fix pull request there first," >&2
    echo "or pass --template-ref main to start from its main branch." >&2
    exit 1
  }
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

# Public projects call the reusable workflows of github-standards, which must be public too.
if [[ "${visibility}" == public ]] &&
  [[ "$(gh api "repos/${standards}" --jq .visibility)" != public ]]; then
  echo "${standards} is private: a public repository cannot call its reusable workflows." >&2
  echo "Make it public first (README, section 3)." >&2
  exit 1
fi

echo "==> Creating ${owner}/${name} (${visibility}) from ${template} ${template_ref}"
gh repo clone "${template}" "${name}" -- --quiet --depth 1 --branch "${template_ref}" \
  -c advice.detachedHead=false
rm -rf "${name}/.git"

# The template's README describes the template: give the copy the project's name.
sed -i "1s/.*/# ${name}/" "${name}/README.md"
if [[ -n "${description}" ]]; then
  DESCRIPTION="${description}" python3 - "${name}/README.md" << 'PY'
import os, sys
path = sys.argv[1]
text = open(path).read()
old = "TODO: replace this title and paragraph with the project name and what it does."
open(path, "w").write(text.replace(old, os.environ["DESCRIPTION"], 1))
PY
fi

create_args=("${owner}/${name}" "--${visibility}")
[[ -z "${description}" ]] || create_args+=(--description "${description}")
gh repo create "${create_args[@]}" > /dev/null

(
  cd "${name}"
  git init --quiet --initial-branch main
  git add --all
  git commit --quiet --message "chore: initialize from repo-template ${template_ref}"
  git remote add origin "https://github.com/${owner}/${name}.git"
  git push --quiet --set-upstream origin main
)

# Settings and rulesets now, while main holds only the initial commit.
ids="$("${here}/apply-settings.sh" "${owner}/${name}")"
main_ruleset_id="$(sed -n 's/^main_ruleset_id=//p' <<< "${ids}")"
tags_ruleset_id="$(sed -n 's/^tags_ruleset_id=//p' <<< "${ids}")"

if ((register)); then
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
  entry="$(printf '    "%s" = {\n      description     = "%s"\n      visibility      = "%s"\n      enforcement     = "active"\n      main_ruleset_id = %s\n      tags_ruleset_id = %s\n    }' \
    "${name}" "${hcl_description}" "${visibility}" "${main_ruleset_id}" "${tags_ruleset_id}")"
  ENTRY="${entry}" MARKER="${marker}" awk '
    index($0, ENVIRON["MARKER"]) { print ENVIRON["ENTRY"] }
    { print }
  ' terraform/projects.tf > terraform/projects.tf.new
  mv terraform/projects.tf.new terraform/projects.tf

  branch="feat/manage-${name,,}"
  title="feat(terraform): manage the ${name} repository"
  git switch --quiet --create "${branch}"
  git add terraform/projects.tf
  git commit --quiet --message "${title}" --message "- add ${name} (${visibility}, from repo-template ${template_ref}) to the projects map with the ids of the rulesets new-repo.sh created, so the next apply imports the repository and both rulesets instead of creating them"
  git push --quiet --set-upstream origin "${branch}"
  gh pr create --repo "${standards}" --head "${branch}" --title "${title}" --body "$(
    cat << BODY
## Description

### Context

\`${owner}/${name}\` was created by \`scripts/new-repo.sh\` from \`repo-template\`
${template_ref}, and \`apply-settings.sh\` already applied the standard settings and the
active rulesets.

### What Changed

- \`terraform/projects.tf\`: \`${name}\` (${visibility}) added to the projects map with the
  ruleset ids (main-protection ${main_ruleset_id}, release-tags ${tags_ruleset_id}).

### How It Was Tested

- \`self-ci\` runs the mocked \`tofu test\`.

### Rollback Plan

Revert this pull request before the apply. After the apply, \`prevent_destroy\` keeps the
repository: remove it from state with \`tofu state rm\` instead.

### Security Notes

None. If the GitHub token for tofu is limited to selected repositories, add \`${name}\` to
it before the plan.

### Checklist

- [ ] \`tofu plan\` reviewed: imports only (repository, two rulesets), no destroy
BODY
  )"
fi

echo
echo "Done: https://github.com/${owner}/${name} (clone in ./${name})"
echo "Next: cd ${name} && make install, then open your first pull request."
