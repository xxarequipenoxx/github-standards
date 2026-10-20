# Security policy

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting (Security tab,
"Report a vulnerability") or contact the maintainer directly. Expect an answer within a
week.

## Supported versions

Only the latest release tag receives fixes. Consumers pin the reusable workflows and the
pre-commit hooks to a release tag; a security fix ships as a new patch tag, picked up through
the Renovate preset (renovate/default.json).

## Practices in this repository

- Secrets never enter Git: gitleaks runs in the pre-commit hooks and in the security.yml
  reusable workflow on every pull request.
- Third-party GitHub Actions are pinned by commit SHA; workflows are audited with actionlint
  and zizmor (.github/zizmor.yml) and run with `permissions: {}` at the top level and
  least-privilege grants per job. A reusable workflow never asks for more than the caller
  contract documented in README section 7.
- terraform/ manages the repositories as code; it is never planned or applied from CI.
- Dependencies are updated through Renovate pull requests and gated by the required checks;
  Dependabot keeps security updates only (.github/dependabot.yml).
