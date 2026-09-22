# AGENTS.md

Conventions for AI agents working in this repository. Account-wide rules (roles, separation
of duties, forbidden actions, security, documentation canvas) live in `~/.ai/` on the
maintainer's machine and are not repeated here.

## What this repository is

Shared engineering standards consumed by every other repository of this account: reusable
GitHub Actions workflows, composite actions, repository settings and rulesets as code,
a Renovate preset, shared pre-commit hooks and the documentation that goes with them.
`README.md` is the implementation brief and the source of truth for scope and milestones.

## Binding rules

- Code, comments, commit messages and documentation are written in English.
- Conventional Commits, checked by commitizen (`.cz.toml`). The pull request title becomes
  the squash commit on `main`, so it is conventional too and it drives the version bump.
- No AI attribution anywhere: no `Co-Authored-By` trailer naming an AI vendor, no
  "generated with" footer, in commits, pull request titles, bodies or code comments.
- One milestone (see the README) per pull request. Never commit on `main`, never merge:
  open a pull request, the human merges.
- Every third-party action is pinned by its full commit SHA with a `# vX.Y.Z` comment on
  the same line. Container images used in workflows are pinned by digest.
- Never use `pull_request_target` or `workflow_run` to run code from a pull request branch.
- User-controlled values (`github.event.pull_request.title`, `body`, branch names, commit
  messages) are passed through `env:` and read as shell variables, never interpolated into
  `run:` blocks.
- Least-privilege `permissions:` per job; `permissions: {}` at the workflow level.
- Run `make check` (actionlint and zizmor) locally before opening a pull request.
- Never run `tofu apply` or change repository settings through the API without an explicit
  go-ahead from the human.
- Stop and ask at every open decision listed in the README.

## Layout

See README.md, section 3.1. Reusable workflows live in `.github/workflows/`, this
repository's own CI in `self-ci.yml` and its own release in `self-release.yml`.
