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

`scripts/new-repo.sh`:

1. copies the **latest release** of `repo-template` into `<owner>/my-project` as its first
   commit (`chore: initialize from repo-template vX.Y.Z`) and clones it in `./my-project`;
2. applies the standard settings and **active** rulesets (`scripts/apply-settings.sh`):
   squash only, PR title and body, delete branch, auto-merge, Dependabot alerts and
   security updates, secret scanning and private vulnerability reporting on public
   repositories, required checks of the template's `pr.yml`;
3. opens a pull request here adding the repository to `terraform/projects.tf` with the
   ruleset ids, so the next reviewed `tofu apply` imports everything with no change.

Then, in the new repository: `make install` (hooks), fill in the README and `AGENTS.md`,
replace the `TODO` language job in `pr.yml`, add the project's ecosystems to
`.github/dependabot.yml`. If the language job adds checks to require, rerun
`make apply-settings REPO=<owner>/my-project CHECKS="commits / conventional commits,..."`
here and copy the list to the project's `required_checks` in `projects.tf`.

Prerequisites, once: this repository public (a public project calls its workflows; README
section 3), the Renovate GitHub App installed for **All repositories**, and at least one
release of `repo-template`.

---

## 2. Existing repository

1. Replace its local CI with thin callers: copy `.github/workflows/pr.yml` and
   `release.yml` from `repo-template`, add the language and deployment jobs (README,
   section 8, has the Onibat example). Keep project-specific workflows (mobile builds) local.
2. Copy `.cz.toml` (or `[tool.commitizen]` in `pyproject.toml`) with the standard values of
   README section 4; they must match exactly, the release workflow depends on them.
3. Copy `.pre-commit-config.yaml`, `renovate.json`, `.github/dependabot.yml`, `.editorconfig`, `.github/zizmor.yml`
   (lets zizmor accept the tag-pinned reusable workflows) and the AI-agent files
   (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) from `repo-template`. Its `dependabot.yml`
   replaces the old one: security updates only, conventional titles. Remove classic branch
   protection when the rulesets go active (Onibat has one), or the old check names block
   every pull request.
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
