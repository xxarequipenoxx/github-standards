# Repositories as code

How the repositories of this account are managed with OpenTofu (README, section 6): what
`terraform/` contains, the one-time setup (state bucket, token), how to import the existing
repositories, how to review a plan, and the order in which the rulesets are switched on.

Nothing here is applied by CI. `self-ci.yml` only runs the static checks and the mocked
tests (`terraform / opentofu`); every `tofu plan` and `tofu apply` is run by hand, and the
plan is reviewed before anything is applied (README, milestone S3).

---

## 1. Layout

```text
terraform/
├── backend.tf                 # S3 backend skeleton: bucket, key, region, endpoint come from backend.hcl
├── providers.tf               # OpenTofu ~> 1.12, integrations/github ~> 6.13.0, owner from a variable
├── variables.tf               # github_owner
├── repositories.tf            # one module call per repository, the required check names
├── outputs.tf                 # enforcement and required checks per repository (plan review)
├── .terraform.lock.hcl        # provider pinned to 6.13.0 (linux and macOS checksums)
├── .tflint.hcl
├── modules/repository/        # one repository: settings, rulesets, Dependabot, Actions access, environments
└── tests/                     # tofu test with mock_provider "github": no token, no API call
```

`modules/repository` manages, per repository:

| Resource | What it sets |
|---|---|
| `github_repository.this` | visibility, description, template flag, issues/wiki/projects/discussions, squash-only merges (`PR_TITLE` / `PR_BODY`), delete branch on merge, auto-merge, update branch, `archive_on_destroy`, `prevent_destroy` |
| `github_repository_ruleset.main` | `main-protection` on the default branch (README, section 5) with the `required_checks` of the repository |
| `github_repository_ruleset.release_tags` | `release-tags` on `refs/tags/v*`: no deletion, no update, no force push; creation left open |
| `github_repository_vulnerability_alerts.this` | Dependabot alerts on |
| `github_repository_dependabot_security_updates.this` | Dependabot security updates on |
| `github_actions_repository_access_level.this[0]` | who may call the repository's reusable workflows (`user` for github-standards, `none` elsewhere); private repositories only |
| `github_repository_environment.this[<name>]` and `..._deployment_policy.this[<name>:branch|tag:<pattern>]` | deployment environments with reviewers and branch/tag policies, when a repository declares any |

Both rulesets share one `enforcement` variable (`disabled` by default). Rulesets on private
repositories need GitHub Pro (README, section 2): without it the plan applies, GitHub stores
the rulesets, and they do not enforce anything.

---

## 2. One-time setup: the state bucket

State is sensitive (it mirrors every repository setting and the numeric ids) and is never
committed. It lives in a versioned OVH Object Storage bucket reached through the S3 API,
locked with `use_lockfile = true` (a lock object next to the state, no DynamoDB).

Create the bucket once by hand, in the OVH control panel or with the `aws` CLI aimed at the
OVH endpoint:

```bash
export AWS_ACCESS_KEY_ID='<S3 access key of a user restricted to this bucket>'
export AWS_SECRET_ACCESS_KEY='<its secret>'
aws --endpoint-url https://s3.<region>.io.cloud.ovh.net --region <region> \
  s3api create-bucket --bucket <state-bucket>
aws --endpoint-url https://s3.<region>.io.cloud.ovh.net --region <region> \
  s3api put-bucket-versioning --bucket <state-bucket> \
  --versioning-configuration Status=Enabled
```

The OVH S3 endpoint has the form `https://s3.<region>.io.cloud.ovh.net` where `<region>` is
the lowercase region code of the bucket (for example `gra`, `sbg`, `rbx`, `de`, `uk`); the
S3 region name is the same code. Use a dedicated S3 user whose policy is limited to this
bucket, as the OVH design of platform-infra (formerly kubernetes-infra) planned for its own
state. Versioning is what lets you recover a previous state after a bad apply.

Then write `terraform/backend.hcl` (gitignored, never committed):

```hcl
bucket = "<state-bucket>"
key    = "github-standards/repositories.tfstate"
region = "<region>"
endpoints = {
  s3 = "https://s3.<region>.io.cloud.ovh.net"
}
```

`backend.tf` already carries `use_lockfile = true` and the `skip_*` flags an S3-compatible
endpoint needs (no IAM, no STS, no AWS checksum extensions). If the endpoint refuses
virtual-hosted bucket URLs, add `use_path_style = true` to `backend.hcl`.

---

## 3. The token

Authentication is the `GITHUB_TOKEN` environment variable, nothing else: no `token`
argument, no variables file, no CI secret (CI never plans).

Create a fine-grained personal access token (Settings, Developer settings, Fine-grained
tokens) with:

| Setting | Value |
|---|---|
| Resource owner | the account that owns the repositories |
| Repository access | Only select repositories: the six managed repositories (see below for creation) |
| Administration | Read and write: repository settings, rulesets, environments and deployment branch policies, Dependabot alerts and security updates, Actions access level, repository creation from a template |
| Contents | Read: the provider reads the repository and its default branch |
| Metadata | Read (added automatically) |
| Expiration | as short as your apply cadence allows; rotate, do not extend |

Verified against the GitHub REST permissions reference for fine-grained tokens on
2026-09-22: every endpoint the module calls (`PATCH /repos/{owner}/{repo}`,
`/rulesets`, `/vulnerability-alerts`, `/automated-security-fixes`, `/environments`,
`/environments/{name}/deployment-branch-policies`, `/actions/permissions/access`,
`/generate`) is under **Administration**. The README lists Actions and Environments read
and write as well; nothing managed here needs them, so they are left out (least privilege).
Add them only when a resource needing them (environment secrets or variables, Actions
permissions) joins the module.

Two traps:

- With `GITHUB_TOKEN` unset, provider 6.x silently falls back to `gh auth token`, the broad
  OAuth token of the GitHub CLI. Export the variable before every command, and prefer a
  subshell so it never lands in your shell history or profile:

  ```bash
  ( export GITHUB_TOKEN="$(cat ~/.config/github-standards/token)"; tofu plan )
  ```

- A fine-grained token restricted to "Only select repositories" cannot create a repository
  that does not exist yet (`from_template = true` on a new module call). For that one apply,
  use a token with access to all repositories, then go back to the restricted one.

---

## 4. First run: init and import the existing repositories

All six repositories already exist on GitHub. **Import them before the first apply**:
without the imports the plan tries to create six repositories with the same names, the API
refuses (`name already exists on this account`) and the apply fails half-way. Every import
is a read: nothing changes on GitHub.

```bash
cd terraform
( export GITHUB_TOKEN="$(cat ~/.config/github-standards/token)"
  export AWS_ACCESS_KEY_ID='<state bucket key>' AWS_SECRET_ACCESS_KEY='<its secret>'

  tofu init -backend-config=backend.hcl

  # Repositories (mandatory: the resource is guarded by prevent_destroy and would be created otherwise).
  tofu import module.github_standards.github_repository.this github-standards
  tofu import module.repo_template.github_repository.this repo-template
  tofu import module.web_kit.github_repository.this web-kit
  tofu import module.kubernetes_infra.github_repository.this platform-infra
  tofu import module.onibat.github_repository.this Onibat
  tofu import module.ai_agentic_setup.github_repository.this ai-agentic-setup

  # Settings that already exist on every repository (their create is an idempotent PUT, so
  # importing is optional; it makes the first plan show the real diff instead of a create).
  for m in github_standards:github-standards repo_template:repo-template web_kit:web-kit \
           kubernetes_infra:platform-infra onibat:Onibat \
           ai_agentic_setup:ai-agentic-setup; do
    tofu import "module.${m%%:*}.github_repository_vulnerability_alerts.this" "${m##*:}"
    tofu import "module.${m%%:*}.github_repository_dependabot_security_updates.this" "${m##*:}"
    tofu import "module.${m%%:*}.github_actions_repository_access_level.this[0]" "${m##*:}"
  done
)
```

Checked on 2026-09-22 for the first five and on 2026-09-28 for ai-agentic-setup (read-only
API calls): none of the six repositories has a ruleset or a deployment environment, so there is nothing else to import; the two rulesets of each
repository are created by the first apply. Should a ruleset appear before then (created in
the UI), import it instead of letting the plan create a duplicate:

```bash
gh api repos/<owner>/<repository>/rulesets --jq '.[] | "\(.id) \(.name)"'
tofu import module.<name>.github_repository_ruleset.main "<repository>:<id>"
tofu import module.<name>.github_repository_ruleset.release_tags "<repository>:<id>"
```

Classic branch protections are a different API and are **not** managed here.

⚠ **Onibat has a classic branch protection on `main`, created by hand** (required checks,
linear history, no force push, no deletion, admins included). Rulesets and classic
protections coexist and both apply, so once the `main-protection` ruleset is `active` and
verified, the human deletes the classic protection in the repository settings (Branches);
otherwise every change of the required checks has to be made twice and the two can
contradict each other. Do not delete it before the ruleset is active: `main` would be
unprotected in between.

---

## 4b. Dry run without a state backend

Before the state bucket exists, or for a quick check of what an apply would change:

```bash
make plan-dry-run          # scripts/terraform-dry-run.sh [--keep]
```

The script copies `terraform/` to a temporary directory, replaces the s3 backend with a local
one (`zz_dry_run_override.tf`), writes import blocks for every repository, ruleset and
setting that already exists on GitHub (`zz_dry_run_imports.tf`, from read-only `gh api`
calls), and runs `tofu plan`. Imports are only previewed: nothing is applied, no state is
written anywhere, and the copy is deleted (`--keep` keeps it). The token is `GITHUB_TOKEN`
when set, else the GitHub CLI session, acceptable because a plan only reads. The summary
counts imports, creates, updates and lists every delete.

Read the plan as in section 5. A dry run is not a substitute for the reviewed apply: the
real apply still needs the backend (section 2) and the restricted token (section 3).

---

## 5. Plan review

```bash
cd terraform
( export GITHUB_TOKEN=...; export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
  tofu plan -out=repositories.tfplan
  tofu show repositories.tfplan
)
```

What to look for, in this order:

1. **No `github_repository` is created or replaced.** Six `update in-place` at most. A
   create means an import is missing; a replace is blocked by `prevent_destroy` and points at
   a ForceNew attribute (`template`): fix the configuration, do not remove the guard.
2. The repository updates are the expected ones: merge commits and rebase merges off,
   squash title and message, delete branch on merge, auto-merge, update branch, wiki and
   projects off (the module defaults; override `has_wiki` / `has_projects` per repository if
   a feature is in use), description where it changes.
3. Two rulesets per repository are created with `enforcement = "disabled"`.
4. `github_actions_repository_access_level`: `user` for github-standards, `none` elsewhere.
5. Nothing under `security_and_analysis`: private repositories on GitHub Pro have no
   Advanced Security; the module does not touch that block.
6. The `repositories` output lists every repository with `enforcement` and its
   `required_checks`, the summary to paste in the pull request that switches a repository
   to `active`.

Apply only that reviewed plan file (`tofu apply repositories.tfplan`), never a fresh plan.
`repositories.tfplan` and the state may contain repository ids and the token is in the
environment, so neither the plan file nor the state is ever committed (`.gitignore`).

---

## 6. Adoption order (README, section 9)

Per repository, one pull request per step where the configuration changes:

1. Merge the caller workflows in the project with the rulesets still `disabled` (this
   milestone ships every repository `disabled`).
2. Open a pull request in the project and read the check names GitHub reports
   (`docs/required-checks.md`, section 4): `gh pr checks <number> --repo <owner>/<repo>`.
3. Set `required_checks` in `repositories.tf` to exactly those names, plan, apply.
4. Switch `enforcement = "active"` in `repositories.tf`, plan, apply. Verify: a direct push
   to `main` is refused, a red pull request cannot be merged, a `v*` tag cannot be deleted.
5. For Onibat only: delete the classic branch protection by hand (section 4).

Doing it in this order avoids a required check that never reports and blocks every pull
request. Emergency switch: set `enforcement = "disabled"` through a pull request, never in
the UI, so Git stays the source of truth.

Current state of the six repositories in `repositories.tf`:

| Module | Repository | `required_checks` | `enforcement` |
|---|---|---|---|
| `github_standards` | github-standards | the 14 names of `self-ci.yml` (`docs/required-checks.md`, section 3) | disabled |
| `repo_template` | repo-template (`is_template = true`) | none yet | disabled |
| `web_kit` | web-kit | none yet | disabled |
| `kubernetes_infra` | platform-infra (renamed from kubernetes-infra) | the template callers plus `plan policies`, `kubernetes`, `checkov`, `trivy config` and `images` | active |
| `onibat` | Onibat | the nine jobs of its current `pr.yml` | disabled |
| `ai_agentic_setup` | ai-agentic-setup | the four jobs of its `pr.yml` (reported on its PR #1) | disabled |

---

## 7. Local checks

What `terraform / opentofu` runs in CI, with the same pinned versions (OpenTofu 1.12.6,
tflint 0.64.0):

```bash
cd terraform
tofu fmt -check -recursive -diff
tofu init -backend=false
tofu validate
tofu test
tflint --init && tflint --format compact --recursive
```

`tofu test` uses `mock_provider "github"`: no token, no network. It covers the README list
(squash-only settings, zero required approvals, the tag ruleset leaving creation open,
`prevent_destroy` present), plus enforcement disabled by default, `required_checks` rendered
into the ruleset, the Actions access level and Dependabot resources, the template block,
environments with reviewers and patterns, the variable validations, and the root wiring
(six repositories, all disabled).
