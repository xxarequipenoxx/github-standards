# Local developer entrypoints. CI runs the same tools with the same pinned versions
# (.github/workflows/self-ci.yml); keep the two in sync.

ACTIONLINT_IMAGE := docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
ZIZMOR_VERSION   := 1.30.1
PRE_COMMIT_VERSION := 4.6.2

.PHONY: help install check actionlint zizmor

help: ## Show the available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

install: ## Install the pre-commit and commit-msg hooks
	uvx pre-commit@$(PRE_COMMIT_VERSION) install --hook-type pre-commit --hook-type commit-msg

check: actionlint zizmor ## Lint and audit the workflows (what self-ci runs)

actionlint: ## Lint .github/workflows with actionlint
	docker run --rm --volume "$(CURDIR):/repo:ro" --workdir /repo $(ACTIONLINT_IMAGE) -color

zizmor: ## Audit .github/workflows with zizmor
	uvx zizmor@$(ZIZMOR_VERSION) --no-progress .github/workflows
