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

`release.yml` runs on `push` to `main`, so its check is never a pull request requirement; it
is listed for completeness.

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

These four names are the `required_checks` value for `github-standards` in `terraform/`
(milestone S3).

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
