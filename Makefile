.DEFAULT_GOAL := help
.PHONY: help test test-system-bash lint check bench bench-home install uninstall exclusions version prep-release release release-beta verify-release

# Which GitHub repo + git remote releases target. Defaults to the project's home
# (AsimovMac/asimov). Pinning GH_REPO to $(REPO) stops another configured remote
# from winning gh's remote-detection.
REPO ?= AsimovMac/asimov
RELEASE_REMOTE ?= origin
export GH_REPO ?= $(REPO)

## —————————— 🎵 Asimov 🎵 ————————————————————————————————————

help: ## Show this help
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

version: ## Print asimov version
	@./bin/asimov --version

exclusions: ## List all paths excluded from Time Machine
	@sudo mdfind "com_apple_backup_excludeItem = 'com.apple.backupd'"


## —————————— 🛠 Development ———————————————————————————————————


# Pin the bash that runs asimov itself. Its shebang is #!/usr/bin/env bash, so
# by default it runs under whichever bash is first on PATH — usually 5.x locally
# and 3.2 for anyone on a stock Mac. Use `make test BASH_BIN=/bin/bash` to check
# what your users actually get; CI runs the matrix for you.
BASH_BIN ?=
# Run tests concurrently (requires GNU parallel: brew install parallel).
BATS_JOBS ?=

test: ## Run Bats tests (BASH_BIN=/bin/bash pins the interpreter; BATS_JOBS=N runs in parallel)
	@BASH_BIN="$(BASH_BIN)" BATS_JOBS="$(BATS_JOBS)" scripts/test.sh

test-system-bash: ## Run Bats tests under the macOS system bash (3.2), as shipped users get
	@$(MAKE) --no-print-directory test BASH_BIN=/bin/bash

lint: ## Run Shellcheck on all shell scripts
	@shellcheck -x --source-path=. bin/asimov
	@shellcheck scripts/install.sh scripts/install-remote.sh scripts/uninstall.sh scripts/prep-release.sh scripts/test.sh tests/test_helper.bash tests/bin/run-tests.sh tests/bin/tmutil tests/bin/mdfind tests/bin/launchctl

check: test lint ## Run tests and linting

## bench: Compare dry-run scan timing: current vs v0.4.2, against tests/fixture
bench:
	@git show v0.4.2:asimov > /tmp/asimov-v042 && chmod +x /tmp/asimov-v042
	@echo "=== v0.4.2 (HOME=tests/fixture) ==="
	@bash -c 'time HOME="$(CURDIR)/tests/fixture" /tmp/asimov-v042 --dry-run'
	@echo ""
	@echo "=== v0.5.x (directory=tests/fixture) ==="
	@bash -c 'time HOME="$(CURDIR)/tests/fixture" ./bin/asimov --dry-run "$(CURDIR)/tests/fixture"'
	@rm -f /tmp/asimov-v042

## bench-home: Compare dry-run scan timing: current vs v0.4.2, against real home directory
bench-home:
	@git show v0.4.2:asimov > /tmp/asimov-v042 && chmod +x /tmp/asimov-v042
	@echo "=== v0.4.2 (full home) ==="
	@bash -c 'time /tmp/asimov-v042 --dry-run'
	@echo ""
	@echo "=== v0.5.x (full home) ==="
	@bash -c 'time ./bin/asimov --dry-run'
	@rm -f /tmp/asimov-v042


## —————————— 📦 Installation ——————————————————————————————————


NAME ?= asimov

install: ## Install Asimov and schedule via launchd (NAME=asimov2 to install under a different name for testing)
	@NAME=$(NAME) scripts/install.sh

uninstall: ## Uninstall Asimov and remove launchd schedule (NAME=asimov2 to remove a non-default install)
	@NAME=$(NAME) scripts/uninstall.sh


## —————————— 🚀 Release ———————————————————————————————————————


prep-release: ## Prepare a release PR (bump version, promote CHANGELOG, branch+commit). Usage: make prep-release VERSION=X.Y.Z
	@VERSION="$(VERSION)" scripts/prep-release.sh

release: check ## Tag and push a stable release — GitHub Actions will create the release
	@set -e; \
	if [ -n "$$(git status --porcelain)" ]; then echo "error: working tree not clean"; exit 1; fi; \
	BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$BRANCH" != "main" ]; then echo "error: releases must be tagged from main (on $$BRANCH)"; exit 1; fi; \
	VERSION=$$(./bin/asimov --version); \
	TAG="v$$VERSION"; \
	if git rev-parse "$$TAG" >/dev/null 2>&1; then echo "error: $$TAG already exists"; exit 1; fi; \
	echo "Tagging $$TAG (signed)..."; \
	git tag -s "$$TAG" -m "Release $$TAG"; \
	git push $(RELEASE_REMOTE) "$$TAG"; \
	echo "Tag $$TAG pushed — GitHub Actions will create the release."; \
	echo "Homebrew: homebrew-core autobumps the formula via BrewTestBot (~3h). Nothing to push."

release-beta: check ## Tag and push a beta pre-release — GitHub Actions will create the pre-release
	@set -e; \
	if [ -n "$$(git status --porcelain)" ]; then echo "error: working tree not clean"; exit 1; fi; \
	VERSION=$$(./bin/asimov --version); \
	BETA_NUM=1; \
	while git tag | grep -q "^v$$VERSION-beta\.$$BETA_NUM$$"; do \
	  BETA_NUM=$$((BETA_NUM + 1)); \
	done; \
	TAG="v$$VERSION-beta.$$BETA_NUM"; \
	echo "Tagging $$TAG (signed)..."; \
	git tag -s "$$TAG" -m "Pre-release $$TAG"; \
	git push $(RELEASE_REMOTE) "$$TAG"; \
	echo "Tag $$TAG pushed — GitHub Actions will create the pre-release."

verify-release: ## brew upgrade asimov and print the version homebrew-core currently serves
	@set -e; \
	brew update; \
	brew upgrade asimov || brew install asimov; \
	"$$(brew --prefix asimov)/bin/asimov" --version; \
	echo "Note: homebrew-core autobumps ~3h after a release, so this may lag the latest tag briefly."
