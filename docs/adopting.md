# Adopting the standards

How a repository of this account comes under the standards: a new project from the
template, or an existing repository moved over. README sections 4, 5 and 9 define the
rules; this page is the checklist.

---

## 1. New project

```bash
make new-repo NAME=my-project          # asks: public or private
make new-repo NAME=my-project VISIBILITY=private
```

`scripts/new-repo.sh` creates `<owner>/my-project` from `repo-template`, clones it into the
current directory and opens a pull request here adding it to `terraform/projects.tf`. Then:

1. Merge that pull request after `self-ci` is green.
2. In `terraform/`: `tofu plan`. Expect one import, the settings update, two rulesets
   created, nothing destroyed. If the tofu token is limited to selected repositories, add
   the new one to it first. Then `tofu apply` (terraform/README.md).
3. In the new repository: `make install` (pre-commit hooks), fill in the README, replace the
   `TODO` language job in `.github/workflows/pr.yml` with the reusable workflow it needs.
4. Open the first pull request, read the check names (`gh pr checks <number>`), set
   `required_checks` on the project's entry if the language job added some, and switch its
   `enforcement` to `"active"` in a pull request here.

A public project calls the reusable workflows of this repository, so this repository must
be public too (README, section 3). The script warns before creating a public project.

---

## 2. Existing repository

1. Replace its local CI with thin callers: copy `.github/workflows/pr.yml` and
   `release.yml` from `repo-template`, add the language and deployment jobs (README,
   section 8, has the Onibat example). Keep project-specific workflows (mobile builds) local.
2. Copy `.cz.toml` (or `[tool.commitizen]` in `pyproject.toml`) with the standard values of
   README section 4; they must match exactly, the release workflow depends on them.
3. Copy `.pre-commit-config.yaml`, `renovate.json`, `.editorconfig` and the AI-agent files
   (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) from `repo-template`. Drop `dependabot.yml` for
   version updates once Renovate runs (Dependabot security updates stay on, managed by
   Terraform).
4. Add a module call in `terraform/repositories.tf` (a repository with its own required
   checks or environments) or an entry in `terraform/projects.tf` (template checks only),
   then import it: `tofu import module.<name>.github_repository.this <repository>`
   (`projects.tf` entries are imported by their `import` block).
5. Follow the adoption order of README section 9: rulesets `disabled`, real check names read
   from a pull request, `required_checks` set, then `active`.

---

## 3. Checklist for a repository under the standards

- [ ] Squash merge only, PR title as the commit subject (Terraform settings)
- [ ] `main-protection` and `release-tags` rulesets `active`, required checks reporting
- [ ] `pr.yml` and `release.yml` call this repository's workflows at a release tag
- [ ] commitizen configuration identical to README section 4
- [ ] pre-commit hooks installed locally (`make install`)
- [ ] Renovate extends `github>xxarequipenoxx/github-standards//renovate/default`
- [ ] No AI attribution in commits, pull request titles or bodies
