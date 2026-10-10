# Required status checks

How GitHub names the status checks produced by the reusable workflows of this repository,
which names each workflow produces, and how to collect the real names from a pull request
before making them required in the `main-protection` ruleset (README, section 5).

---

## 1. How a check name is formed

A caller workflow in a project (for example `pr.yml`) declares a job whose `uses:` points at
a reusable workflow of this repository. GitHub reports one status check per job of the
reusable workflow, named from both sides:

```text
<caller job id> / <reusable job name>

caller pr.yml, job id "commits"  --uses-->  commits.yml, job name "conventional commits"
                                  --reports-->  status check "commits / conventional commits"
```

- `<caller job id>` is the key of the job in the caller workflow (`commits:`, `security:`).
- `<reusable job name>` is the `name:` of the job inside the reusable workflow (falls back
  to the job id when no `name:` is set).

The caller decides the first half, so two projects calling the same workflow under different
job ids produce different check names. Names must be unique inside one repository: an
ambiguous required check blocks every merge.

---

## 2. Names produced by each reusable workflow

The table assumes the caller job ids of the README examples (section 8). Replace the first
half if a project uses different job ids.

| Reusable workflow | Job name inside the workflow | Suggested caller job id | Resulting check name |
|---|---|---|---|
| `commits.yml` | `conventional commits` | `commits` | `commits / conventional commits` |
| `security.yml` | `gitleaks` | `security` | `security / gitleaks` |
| `security.yml` | `zizmor` | `security` | `security / zizmor` |
| `release.yml` | `release` | `version` | `version / release` |
| `python-uv.yml` | `lint and types` | `python` | `python / lint and types` |
| `python-uv.yml` | `tests (sqlite)` | `python` | `python / tests (sqlite)` |
| `python-uv.yml` | `tests (postgresql <version>)`, one per entry of `postgres-versions` | `python` | `python / tests (postgresql 16)` |
| `python-uv.yml` | `dependency audit` | `python` | `python / dependency audit` |
| `container.yml` | `container build` | `image` | `image / container build` |
| `container.yml` | `container sign` (only when `sign` and `push` are true) | `image` | `image / container sign` |
| `oci-manifests.yml` | `oci manifests` | `manifests` | `manifests / oci manifests` |
| `oci-manifests.yml` | `oci manifests sign` (only when `sign` and `push` are true) | `manifests` | `manifests / oci manifests sign` |
| `opentofu.yml` | `opentofu` | `opentofu` | `opentofu / opentofu` |
| `kubernetes-manifests.yml` | `kustomize and kubeconform` | `manifests` | `manifests / kustomize and kubeconform` |
| `kubernetes-manifests.yml` | `sops encrypted` (only when `check-sops` is true) | `manifests` | `manifests / sops encrypted` |

`release.yml`, `container.yml` and `oci-manifests.yml` run on `push` to `main` in the README
examples, so their checks are never pull request requirements; they are listed for
completeness. A project that builds its image on pull requests too (`push: false`) gets
`image / container build` as a requirable check.

The PostgreSQL job name carries the version: adding or removing a version in
`postgres-versions` changes the set of check names, so update `required_checks` in the same
change. The conditional jobs (`container sign`, `oci manifests sign`, `sops encrypted`) are
skipped, not absent, when their input is false; a skipped required check counts as passed.

---

## 3. Names produced in this repository

`self-ci.yml` runs on every pull request of this repository and calls the reusable workflows
locally, which gives the fixture coverage the README asks for.

| Workflow | Job | Check name |
|---|---|---|
| `self-ci.yml` | `lint` | `actionlint and zizmor` |
| `self-ci.yml` | `commits` (calls `commits.yml`) | `commits / conventional commits` |
| `self-ci.yml` | `security` (calls `security.yml`) | `security / gitleaks` |
| `self-ci.yml` | `security` (calls `security.yml`) | `security / zizmor` |
| `self-ci.yml` | `python` (calls `python-uv.yml` on `tests/fixtures/python-uv`) | `python / lint and types` |
| `self-ci.yml` | `python` (calls `python-uv.yml` on `tests/fixtures/python-uv`) | `python / tests (sqlite)` |
| `self-ci.yml` | `python` (calls `python-uv.yml` on `tests/fixtures/python-uv`) | `python / tests (postgresql 17)` |
| `self-ci.yml` | `python` (calls `python-uv.yml` on `tests/fixtures/python-uv`) | `python / dependency audit` |
| `self-ci.yml` | `container` (calls `container.yml` on `tests/fixtures/container`, no push) | `container / container build` |
| `self-ci.yml` | `manifests` (calls `oci-manifests.yml` on `tests/fixtures/kustomize`, no push) | `manifests / oci manifests` |
| `self-ci.yml` | `opentofu` (calls `opentofu.yml` on `tests/fixtures/opentofu`) | `opentofu / opentofu` |
| `self-ci.yml` | `kubernetes` (calls `kubernetes-manifests.yml` on `tests/fixtures/kustomize`) | `kubernetes / kustomize and kubeconform` |
| `self-ci.yml` | `kubernetes` (calls `kubernetes-manifests.yml` on `tests/fixtures/kustomize`) | `kubernetes / sops encrypted` |
| `self-ci.yml` | `terraform` (calls `opentofu.yml` on `terraform`, mocked `tofu test`) | `terraform / opentofu` |
| `self-ci.yml` | `hooks` (shellcheck and `tests/hooks/run.sh`) | `hook tests` |

These names are the `required_checks` value for `github-standards` in
`terraform/repositories.tf` (milestone S3). The `container sign` and `oci manifests sign`
jobs are skipped in the fixtures (no push, no signing) and are not listed.

---

## 4. Collecting the names from a real pull request

Read the names as GitHub reports them instead of deriving them by hand, then set
`required_checks` and switch the ruleset to `active` (README, section 9).

```bash
gh pr checks <number> --repo <owner>/<repository>
gh api "repos/<owner>/<repository>/commits/<head sha>/check-runs" --jq '.check_runs[].name'
```

---

## 5. Pitfalls

| Pitfall | Impact | Mitigation |
|---|---|---|
| Renaming a job in a reusable workflow | Every consumer's required check stops reporting and blocks merges | A job `name:` is part of the public contract; renaming it is a breaking change |
| Two caller jobs with the same id in one repository | Ambiguous required check | Job ids are unique per workflow file, but keep them unique across files too |
| A required check that never runs (path filter, skipped job) | The pull request cannot be merged | Do not path-filter the workflows that produce required checks; roll out with the ruleset in `disabled` mode first |
| Check names contain spaces | Copy errors in `required_checks` | Copy the names from `gh pr checks` output |

Rules of thumb: set the job `name:` explicitly in every reusable workflow, keep caller job
ids identical across projects (`commits`, `security`, `version`) so the `required_checks`
lists stay identical too, and follow the README adoption order: callers merged with the
ruleset `disabled`, names read from a pull request, `required_checks` set, ruleset `active`.
