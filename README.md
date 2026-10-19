# github-standards

Shared engineering standards for all my GitHub repositories: branch policy on `main`,
Conventional Commits and automatic versioning with commitizen, reusable CI/CD workflows,
repository settings as code, and a template for new projects. Every project (starting with
`onibat` and `kubernetes-infra`) consumes these instead of copying YAML around.

> **Status: specification.** This README is the implementation brief. Build it milestone by
> milestone (see [Milestones](#milestones)); each milestone is one pull request.

---

## 1. Principles

- **One source of truth, pinned consumption.** Logic lives here once. Projects call it
  through reusable workflows pinned to a release tag (`@vX.Y.Z`); Renovate proposes
  upgrades as pull requests. Nothing changes in a project without a PR in that project.
- **`main` is always releasable and only changes through a green PR.** No direct pushes,
  no force pushes, squash merges only, linear history.
- **Versions come from Git tags only.** commitizen computes the next SemVer from the
  commits, the pipeline creates the tag and the GitHub release. **Nothing is ever committed
  back to `main`**, so the branch policy needs no bypass for bots.
- **Everything as code.** Repository settings and rulesets are managed with OpenTofu, not
  clicked in the UI, so all repositories stay identical and drift is visible.
- **Secure CI by default.** Least-privilege `permissions:` per job, third-party actions
  pinned by commit SHA, no `pull_request_target` running PR code, secret scanning on every PR.

---

## 2. Prerequisite: GitHub Pro

Rulesets and protected branches on **private** repositories require GitHub Pro (or Team).
On GitHub Free they only apply to public repositories. Without Pro the rules below cannot
be enforced on `onibat` or `kubernetes-infra`; the CI checks still run, but a red PR could
be merged.

---

## 3. Two repositories

| Repository | Visibility | Role |
|---|---|---|
| `github-standards` (this one) | public, so public projects can call its workflows (private projects call them too) | reusable workflows, composite actions, repository settings and rulesets as code, Renovate preset, shared hooks, docs |
| `repo-template` | private, `is_template = true` | skeleton for new projects: thin caller workflows, commitizen config, pre-commit, AGENTS.md, PR template |

Private reusable workflows can be called only from **private** repositories of the same
owner. If a project ever becomes public, it needs a public copy of the workflows it uses.

### 3.1 `github-standards` layout

```
github-standards/
├── README.md
├── AGENTS.md                       # CLAUDE.md and GEMINI.md contain one line pointing here
├── .github/workflows/
│   ├── commits.yml                 # reusable: Conventional Commits + no-AI-attribution check
│   ├── release.yml                 # reusable: next version, tag, GitHub release
│   ├── container.yml               # reusable: build and push image to GHCR, outputs digest
│   ├── oci-manifests.yml           # reusable: pin image digest in a Kustomize overlay, flux push artifact
│   ├── python-uv.yml               # reusable: uv, ruff, mypy, pytest (+ PostgreSQL matrix), pip-audit
│   ├── opentofu.yml                # reusable: fmt, validate, test, tflint
│   ├── kubernetes-manifests.yml    # reusable: kustomize build + kubeconform (+ CRD schemas), SOPS check
│   ├── security.yml                # reusable: gitleaks, zizmor (workflow static analysis)
│   ├── ai-review.yml               # reusable, optional: one AI reviewer on PRs
│   ├── self-ci.yml                 # CI of this repo (actionlint, zizmor, tofu, tests of the scripts)
│   └── self-release.yml            # releases this repo with its own release.yml
├── actions/
│   ├── setup-tools/action.yml      # installs pinned kustomize, kubeconform, flux, sops, age, tofu
│   └── lowercase/action.yml        # lowercases owner/repo for OCI references
├── hooks/                          # pre-commit hooks (.pre-commit-hooks.yaml at repo root)
│   ├── no-ai-attribution.sh        # commit-msg stage
│   └── sops-encrypted.sh           # fails if a *.sops.yaml file is not encrypted
├── renovate/default.json           # shared Renovate preset
├── scripts/new-repo.sh             # make new-repo: create a project from repo-template (section 6)
├── terraform/                      # repositories as code (section 6)
│   ├── modules/repository/         # settings + rulesets + environments for one repository
│   ├── repositories.tf             # one module call per repository
│   ├── projects.tf                 # projects created by new-repo.sh, one map entry each
│   └── tests/                      # tofu test with a mocked provider
└── docs/
    ├── adopting.md                 # how to move an existing repository to the standards
    └── required-checks.md          # how status check names are formed
```

### 3.2 `repo-template` layout

```
repo-template/
├── .github/
│   ├── workflows/pr.yml            # thin caller: commits, security, + language job (TODO marker)
│   ├── workflows/release.yml       # thin caller: release (+ container / manifests if needed)
│   └── pull_request_template.md
├── .cz.toml                        # commitizen config (section 4); Python projects use pyproject.toml
├── .pre-commit-config.yaml         # commitizen commit-msg, no-AI-attribution, gitleaks, basic hooks
├── .editorconfig
├── .gitignore
├── AGENTS.md  CLAUDE.md  GEMINI.md # conventions, the last two point to AGENTS.md
├── Makefile                        # install (hooks), check, fmt
├── README.md                       # skeleton
└── renovate.json                   # { "extends": ["github>OWNER/github-standards//renovate/default"] }
```

A template is a one-time copy. That is fine here because the copied workflows are only
thin callers; the logic keeps evolving in `github-standards` and reaches projects through
Renovate PRs.

---

## 4. Versioning standard (commitizen)

```toml
# .cz.toml  (or [tool.commitizen] in pyproject.toml)
[tool.commitizen]
name = "cz_conventional_commits"
version_provider = "scm"          # version read from Git tags, never written to files
tag_format = "v$version"
major_version_zero = true         # until 1.0.0: breaking changes bump the minor
update_changelog_on_bump = false  # release notes go to the GitHub release, not to a file
annotated_tag = true
```

- `feat` bumps the minor version; `fix` and `perf` bump the patch; `!` or
  `BREAKING CHANGE` bumps the major (after 1.0.0). `docs`, `chore`, `ci`, `test`,
  `refactor`, `style` and `build` release nothing.
- With squash merges, **the PR title becomes the commit on `main`**, so the PR title is
  what gets checked and what drives the bump. Branch commits are checked too, but only as
  hygiene.
- Release flow (reusable `release.yml`):
  1. recovery first: if `HEAD` already carries a `v*` tag without a GitHub release (a
     previous run failed after pushing the tag), the job publishes that release and skips
     steps 2 and 3; with the release present it succeeds with `released=false`;
  2. `cz bump --get-next --yes`; exit code 21 (nothing eligible) or 3 (no new commit), or a
     next version equal to the current one, means no release, and the job succeeds with
     `released=false`;
  3. otherwise it creates the annotated tag `vX.Y.Z` with the `GITHUB_TOKEN` and pushes it;
  4. it creates the GitHub release, whose notes are the first section of
     `cz changelog --dry-run vX.Y.Z`;
  5. outputs: `released`, `version` (without the `v`), `tag`.
  Downstream jobs (image, manifests) run only if `released == 'true'`.

Scopes: free-form but consistent within a project (the package or directory name). A
project can restrict them in its own `.cz.toml`.

---

## 5. Branch policy (rulesets)

Applied to every repository by the Terraform module (section 6).

**Ruleset `main-protection`** (target: branch, `~DEFAULT_BRANCH`)

| Rule | Value | Why |
|---|---|---|
| Restrict deletions | on | |
| Block force pushes | on | |
| Require linear history | on | squash only |
| Require signed commits | on | free here: squash merges made by GitHub (web UI, `gh pr merge`, auto-merge, Renovate) are signed by GitHub, so no local signing setup is needed |
| Require a pull request | on, **0 required approvals** | I work alone and GitHub does not let an author approve their own PR; 1 approval would block every merge |
| Dismiss stale approvals, require conversation resolution | on | |
| Allowed merge methods | `squash` | |
| Required status checks | per repository (variable), strict (branch up to date) | |
| Bypass list | empty | emergencies: set `enforcement = "disabled"` through Terraform, in a PR |

**Ruleset `release-tags`** (target: tag, `refs/tags/v*`)

| Rule | Value | Why |
|---|---|---|
| Restrict deletions | on | a published version never disappears |
| Restrict updates, block force pushes | on | a tag never moves |
| Restrict creations | **off** | the release workflow creates tags with `GITHUB_TOKEN`; restricting creation would need a bypass actor |

**Repository settings**: squash merge only, squash commit title `PR_TITLE` and message
`PR_BODY`, delete branch on merge, allow auto-merge, allow update branch, Dependabot
vulnerability alerts (`github_repository_vulnerability_alerts`), Dependabot security
updates, `archive_on_destroy = true` plus `prevent_destroy` (Terraform must never delete a
repository).

**Status check names** from reusable workflows have the form
`<caller job id> / <reusable job name>`, for example `commits / conventional commits`.
Names must be unique across a repository's workflows, otherwise the required check is
ambiguous and blocks merges. `docs/required-checks.md` lists the names produced by each
reusable workflow.

---

## 6. Repositories as code (`terraform/`)

- Provider **`integrations/github` ~> 6.13** (verified 2026-09-21), OpenTofu 1.12.x.
- Authentication: a fine-grained personal access token limited to the managed repositories
  (Administration, Actions, Environments: read and write; Contents, Metadata: read), passed
  as `GITHUB_TOKEN` in the environment. Never in state or variables files.
- State: same S3 backend pattern as kubernetes-infra (versioned bucket, `use_lockfile = true`).
- `modules/repository` inputs: `name`, `description`, `visibility`, `from_template`
  (creates the repository from `repo-template` via the `template` block),
  `required_checks` (list), `enforcement` (`active`/`disabled`),
  `environments` (name, required reviewers, deployment branch policy),
  `actions_access_level` (`none` by default, `user` for `github-standards`).
- `repositories.tf`: `github-standards`, `repo-template`, `web-kit`, `kubernetes-infra`, `onibat`,
  `ai-agentic-setup`
  (the existing repository is named `Onibat`: import it with `tofu import`, do not recreate it).
- New projects: `make new-repo NAME=<name>` asks only public or private, copies the latest
  `repo-template` release into the new repository, applies the settings and **active**
  rulesets at once through the API (`scripts/apply-settings.sh`, same values as the module;
  the template's check names are known, so no disabled phase), and opens a pull request here
  adding it to `terraform/projects.tf` with the ruleset ids. `import` blocks make the next
  reviewed apply adopt everything with no change. `scripts/apply-settings.sh <owner>/<repo>`
  brings an existing repository to the same settings. A public project needs this repository
  public too (section 3).
- Dependencies: Renovate does every version update (shared preset); Dependabot does
  security updates only (setting on, `open-pull-requests-limit: 0` and conventional prefixes
  in each project's `dependabot.yml`).
- Tests (`tofu test`, mocked provider): squash-only settings, `required_approving_review_count == 0`,
  tag ruleset does not restrict creation, `prevent_destroy` present.

Reference implementation of the two rulesets (validated with `tofu validate` against
provider 6.13.0):

```hcl
resource "github_repository_ruleset" "main" {
  name        = "main-protection"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    required_signatures     = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      dynamic "required_check" {
        for_each = toset(var.required_checks)
        content {
          context = required_check.value
        }
      }
    }
  }
}

resource "github_repository_ruleset" "release_tags" {
  name        = "release-tags"
  repository  = github_repository.this.name
  target      = "tag"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    update           = true
    non_fast_forward = true
  }
}
```

---

## 7. Reusable workflows

All are `on: workflow_call`, declare the minimum `permissions` per job, pin third-party
actions by SHA, and set `concurrency` where it matters. Callers pass secrets explicitly (or
`secrets: inherit`, which is acceptable between private repositories of the same owner).

| Workflow | Inputs | Outputs | Caller permissions |
|---|---|---|---|
| `commits.yml` | `ai-attribution-check` (bool, default true) | | `contents: read`, `pull-requests: read` |
| `release.yml` | | `released`, `version`, `tag` | `contents: write` |
| `container.yml` | `image-name`, `version`, `context`, `dockerfile`, `platforms`, `sign` (bool), `build-secrets` (multiline `id=value`, forwarded to BuildKit), `push` (bool, default true) | `image`, `digest` | `contents: read`, `packages: write`, `id-token: write` if signing |
| `oci-manifests.yml` | `image-name`, `image-digest`, `version`, `path` (e.g. `deploy`), `overlay`, `artifact-name`, `crd-schema-locations`, `sign`, `push` (bool, default true) | `artifact` | `contents: read`, `packages: write`, `id-token: write` if signing |
| `python-uv.yml` | `python-version`, `postgres-versions` (JSON list, empty = none), `coverage-threshold`, `working-directory`, `playwright-browsers` (comma list, empty = none), `apt-packages` (space list, empty = none), `git-credentials` (bool; secret `GIT_READ_TOKEN`) | | `contents: read` |
| `opentofu.yml` | `working-directory`, `tofu-version`, `run-tests` | | `contents: read` |
| `kubernetes-manifests.yml` | `paths` (JSON list), `crd-schema-locations`, `check-sops` | | `contents: read` |
| `security.yml` | | | `contents: read`, `security-events: write` (SARIF upload) |
| `auto-merge.yml` | secret `token` (`AUTO_MERGE_TOKEN`) | | `contents: read` |
| `ai-review.yml` | `assistant` (`claude`/`codex`/`gemini`), `prompt-file` | | `contents: read`, `pull-requests: write`, `issues: write` |

Behaviour details:

- **`commits.yml`**:
  - `cz check --rev-range <base>..<head>` on the branch commits and `cz check --message`
    on the PR title, both passed through `env:` (never interpolated into the script:
    injection risk);
  - AI-attribution check on commit messages, the PR title and the PR body: fails on lines matching
    `(?i)^co-authored-by:.*(claude|anthropic|copilot|chatgpt|openai|codex|gemini)` or
    `(?i)generated (with|by) .*(claude|copilot|chatgpt|codex|gemini)`. The PR title and body
    become the squash commit subject and message, so both must be clean too.
- **`container.yml`**:
  - image `ghcr.io/<lowercased owner>/<image-name>` (the owner or repository name may
    contain uppercase letters; OCI references must be lowercase);
  - tags `X.Y.Z`, `X.Y` and `sha-<short>`;
  - SBOM and provenance attestations; digest exposed as output;
  - `build-secrets`: one `id=value` per line, forwarded to `docker/build-push-action`
    `secrets:` for `RUN --mount=type=secret,id=<id>` steps (the web-kit git token); pass a
    secrets expression, never a literal;
  - `push: false` builds with the same exporter without any registry write (pull request
    builds, fixtures); the digest is still returned. `sign` needs `push`.
- **`oci-manifests.yml`**: copies `path`, runs
  `kustomize edit set image <name>=<image>@<digest>` in `overlay`, validates with
  kubeconform, then
  `flux push artifact oci://ghcr.io/<owner>/<artifact-name>:<version> --source=<repo URL> --revision=v<version>@sha1:<sha>`.
  Nothing is committed back. The base manifests reference the image as
  `ghcr.io/<owner>/<image-name>` (that is the name `set image` matches). `push: false`
  builds the artifact locally (`flux build artifact`) without any registry write.
- **`python-uv.yml`**: `uv sync --frozen`, `ruff check`, `ruff format --check`, `mypy`,
  `pytest` with the coverage gate (SQLite, plus one job per PostgreSQL version as a service
  container, which exports `TEST_DATABASE_URL` and the libpq `PG*` variables), `pip-audit`
  on the exported lock;
  - `apt-packages`: Debian packages installed with apt before pytest in both test jobs
    (`ffmpeg` for media projects); names are validated before the install;
  - `playwright-browsers`: comma list installed with `playwright install --with-deps`
    before pytest (the project must depend on `playwright`); empty installs nothing;
  - `git-credentials`: when true, git rewrites `https://github.com/` to use the
    `GIT_READ_TOKEN` secret (`url.insteadOf`) before `uv sync --frozen`, for private git
    dependencies such as web-kit; the token stays in `env:` and is never printed.
- **`security.yml`**: gitleaks on the full history of the PR range, zizmor on
  `.github/workflows/`.
- **`auto-merge.yml`**: turns on GitHub auto-merge (squash) for every pull request that does
  not announce a breaking change, and turns it off when a later push or edit announces one:
  - breaking change: `!` before the colon of the header, or a `BREAKING CHANGE:` /
    `BREAKING-CHANGE:` footer, in the PR title, the PR body or any branch commit; those pull
    requests wait for a human merge;
  - only when the target branch has active required status checks (otherwise GitHub would
    merge before any check ran); drafts and forks are skipped;
  - needs the secret `AUTO_MERGE_TOKEN` (fine-grained token, Contents and Pull requests read
    and write): a merge done by auto-merge turned on with `GITHUB_TOKEN` triggers no push
    workflow, so `release.yml` would never run. Without the secret the job only warns;
  - caller trigger `pull_request` with `edited` and `ready_for_review`, so a title change
    or a draft becoming ready is re-evaluated. Never a required check.

`actions/setup-tools` pins versions in one place (verified 2026-09-21: OpenTofu 1.12.6,
kustomize 5.8.1, kubeconform 0.8.0, flux 2.9.5, sops 3.13.3, age 1.3.2, commitizen 4.x)
and is kept current by a Renovate regex manager.

---

## 8. Caller examples (what a project contains)

`onibat/.github/workflows/pr.yml`:

```yaml
name: pr
on:
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, edited]
permissions:
  contents: read
concurrency:
  group: pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  commits:
    uses: OWNER/github-standards/.github/workflows/commits.yml@v1.0.0
    permissions:
      contents: read
      pull-requests: read
  python:
    uses: OWNER/github-standards/.github/workflows/python-uv.yml@v1.0.0
    with:
      postgres-versions: '["16"]'
      coverage-threshold: 80
  manifests:
    uses: OWNER/github-standards/.github/workflows/kubernetes-manifests.yml@v1.0.0
    with:
      paths: '["deploy/overlays/production"]'
  security:
    uses: OWNER/github-standards/.github/workflows/security.yml@v1.0.0
    permissions:
      contents: read
      security-events: write
```

`onibat/.github/workflows/release.yml`:

```yaml
name: release
on:
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: release
  cancel-in-progress: false
jobs:
  version:
    uses: OWNER/github-standards/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
  image:
    needs: version
    if: needs.version.outputs.released == 'true'
    uses: OWNER/github-standards/.github/workflows/container.yml@v1.0.0
    permissions:
      contents: read
      packages: write
    with:
      image-name: onibat
      version: ${{ needs.version.outputs.version }}
  manifests:
    needs: [version, image]
    uses: OWNER/github-standards/.github/workflows/oci-manifests.yml@v1.0.0
    permissions:
      contents: read
      packages: write
    with:
      image-name: onibat
      image-digest: ${{ needs.image.outputs.digest }}
      version: ${{ needs.version.outputs.version }}
      path: deploy
      overlay: overlays/production
      artifact-name: onibat-deploy
```

---

## 9. Adopting the standards in existing repositories

- **onibat**:
  - replace the current `pr.yml` and `release.yml` with the callers above (the logic they
    contain today moves into the reusable workflows);
  - keep `mobile.yml` local, it is project-specific;
  - move `[tool.commitizen]` to the standard values of section 4 (they already match);
  - import the repository into Terraform and apply the rulesets.
- **kubernetes-infra**: created from `repo-template` by Terraform; its CI uses
  `opentofu.yml`, `kubernetes-manifests.yml`, `commits.yml` and `security.yml`. It needs no
  release job (no versions).
- Order for each repository:
  1. merge the callers with the rulesets in `disabled` mode;
  2. read the real check names from a PR;
  3. set `required_checks`;
  4. switch to `active`.

  Doing it in this order avoids a required check that never reports and blocks every PR.

---

## 10. Shared pre-commit hooks and Renovate

- `.pre-commit-hooks.yaml` exposes `no-ai-attribution` (stage `commit-msg`) and
  `sops-encrypted`. Pre-commit clones this private repository with your local Git
  credentials; CI does not rely on it (the reusable workflows perform the same checks).
- `renovate/default.json`:
  - weekly schedule; minor and patch updates grouped;
  - auto-merge of patch updates for GitHub Actions and reusable workflow refs (safe because
    the required checks gate them);
  - managers enabled: `github-actions` (includes `uses: owner/repo/.github/workflows/x.yml@vX`),
    `terraform`, `flux`, `pep621`/uv, `dockerfile`, plus a regex manager for
    `actions/setup-tools`.
  - The Renovate GitHub App must be granted access to this repository so that projects can
    extend the private preset.

---

## Milestones

| # | Scope | Acceptance criteria |
|---|---|---|
| S0 | Repo skeleton, AGENTS.md, `self-ci.yml` (actionlint, zizmor) | CI green |
| S1 | `commits.yml`, `release.yml`, `security.yml`, `self-release.yml`; first tag `v0.1.0` of this repo created by its own pipeline | a PR with a non-conventional title or an AI trailer fails; a `feat:` merge produces a tag and a GitHub release; a `docs:` merge produces nothing |
| S2 | `python-uv.yml`, `container.yml`, `oci-manifests.yml`, `opentofu.yml`, `kubernetes-manifests.yml`, `actions/*` | each workflow exercised by a fixture job in `self-ci.yml` |
| S3 | `terraform/` module + tests; manage `github-standards` and `repo-template` | `tofu test` green; **stop for my review of `tofu plan` before apply** |
| S4 | `repo-template`, Renovate preset, hooks, `docs/` | a repository created from the template passes its first PR |
| S5 | Adoption: onibat (import + callers), kubernetes-infra (created from the template) | rulesets active; direct push to `main` refused; a red PR cannot be merged; the onibat release publishes the image and the `onibat-deploy` artifact |

## Rules for the implementing agent

- Code, comments and docs in English. Conventional Commits. **No AI attribution** in
  commits, PR titles or PR bodies.
- One milestone per PR. Pin every third-party action by full commit SHA with a version
  comment. Run actionlint and zizmor locally before opening a PR.
- Never use `pull_request_target` or `workflow_run` to run code from a PR branch.
  User-controlled values (`github.event.pull_request.title`, `body`, branch names) go
  through `env:`, never inline in `run:`.
- Never run `tofu apply` or change repository settings through the API without my explicit
  go-ahead.
- Stop and ask at every [open decision](#open-decisions).

## Open decisions

- Subscribe to GitHub Pro (required for rulesets on private repositories)?
- Which AI assistant for `ai-review.yml`, if any: Claude, Codex or Gemini (one only, to
  avoid three reviews per PR).
- Keep `major_version_zero = true` until the first real production release of each project?
- Final repository names (`github-standards`, `repo-template`).
