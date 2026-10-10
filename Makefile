# Local developer entrypoints. CI runs the same tools with the same pinned versions
# (.github/workflows/self-ci.yml); keep the two in sync.

ACTIONLINT_IMAGE := docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
ZIZMOR_VERSION   := 1.30.1
PRE_COMMIT_VERSION := 4.6.2

.PHONY: help install check actionlint zizmor test-hooks new-repo apply-settings

help: ## Show the available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

install: ## Install the pre-commit and commit-msg hooks
	uvx pre-commit@$(PRE_COMMIT_VERSION) install --hook-type pre-commit --hook-type commit-msg

check: actionlint zizmor ## Lint and audit the workflows (what self-ci runs)

actionlint: ## Lint .github/workflows with actionlint
	docker run --rm --volume "$(CURDIR):/repo:ro" --workdir /repo $(ACTIONLINT_IMAGE) -color

zizmor: ## Audit .github/workflows with zizmor
	uvx zizmor@$(ZIZMOR_VERSION) --no-progress .github/workflows

test-hooks: ## Shellcheck and test the shared hooks and scripts (what the hook tests job runs)
	shellcheck hooks/*.sh scripts/*.sh tests/hooks/*.sh
	bash tests/hooks/run.sh

new-repo: ## Create a project from repo-template: make new-repo NAME=my-project [VISIBILITY=public|private]
	@test -n "$(NAME)" || { echo "usage: make new-repo NAME=my-project [VISIBILITY=public|private]"; exit 2; }
	scripts/new-repo.sh "$(NAME)" $(if $(VISIBILITY),--$(VISIBILITY))

apply-settings: ## Apply the standard settings and rulesets: make apply-settings REPO=owner/name [CHECKS="a,b"]
	@test -n "$(REPO)" || { echo "usage: make apply-settings REPO=owner/name [CHECKS=\"a,b\"]"; exit 2; }
	scripts/apply-settings.sh "$(REPO)" $(if $(CHECKS),--checks "$(CHECKS)")
