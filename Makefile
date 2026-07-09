.DEFAULT_GOAL := help
.PHONY: help test lint check bench bench-home install uninstall exclusions version prep-release release release-beta bump-formula ship-formula verify-release

TAP_DIR ?= ../homebrew-tap

# Which GitHub repo + git remote releases target. Defaults to the project's home
# (AsimovMac/asimov); override for the interim django23 tap flow, e.g.:
#   make release-beta REPO=django23/asimov RELEASE_REMOTE=origin
# Pinning GH_REPO to $(REPO) stops another configured remote from winning gh's
# remote-detection — bit us in 0.6.4 when ship-formula hit an upstream release.yml
# and 404'd.
REPO ?= AsimovMac/asimov
RELEASE_REMOTE ?= origin
export GH_REPO ?= $(REPO)

## —————————— 🎵 Asimov 🎵 ————————————————————————————————————

help: ## Show this help
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

version: ## Print asimov version
	@./asimov --version

exclusions: ## List all paths excluded from Time Machine
	@sudo mdfind "com_apple_backup_excludeItem = 'com.apple.backupd'"


## —————————— 🛠 Development ———————————————————————————————————


test: ## Run Bats tests
	@bats tests/sentinels.bats tests/behavior.bats tests/cache.bats tests/format.bats tests/plist.bats

lint: ## Run Shellcheck on all shell scripts
	@shellcheck asimov scripts/install.sh scripts/install-remote.sh scripts/uninstall.sh scripts/prep-release.sh tests/test_helper.bash tests/bin/run-tests.sh tests/bin/tmutil tests/bin/mdfind

check: test lint ## Run tests and linting

## bench: Compare dry-run scan timing: current vs v0.4.2, against tests/fixture
bench:
	@git show v0.4.2:asimov > /tmp/asimov-v042 && chmod +x /tmp/asimov-v042
	@echo "=== v0.4.2 (HOME=tests/fixture) ==="
	@bash -c 'time HOME="$(CURDIR)/tests/fixture" /tmp/asimov-v042 --dry-run'
	@echo ""
	@echo "=== v0.5.x (directory=tests/fixture) ==="
	@bash -c 'time HOME="$(CURDIR)/tests/fixture" ./asimov --dry-run "$(CURDIR)/tests/fixture"'
	@rm -f /tmp/asimov-v042

## bench-home: Compare dry-run scan timing: current vs v0.4.2, against real home directory
bench-home:
	@git show v0.4.2:asimov > /tmp/asimov-v042 && chmod +x /tmp/asimov-v042
	@echo "=== v0.4.2 (full home) ==="
	@bash -c 'time /tmp/asimov-v042 --dry-run'
	@echo ""
	@echo "=== v0.5.x (full home) ==="
	@bash -c 'time ./asimov --dry-run'
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
	VERSION=$$(./asimov --version); \
	TAG="v$$VERSION"; \
	if git rev-parse "$$TAG" >/dev/null 2>&1; then echo "error: $$TAG already exists"; exit 1; fi; \
	echo "Tagging $$TAG (signed)..."; \
	git tag -s "$$TAG" -m "Release $$TAG"; \
	git push $(RELEASE_REMOTE) "$$TAG"; \
	echo "Tag $$TAG pushed — GitHub Actions will create the release."; \
	echo "Next: run 'make ship-formula' to wait for release.yml, bump the tap formula, and push."

release-beta: check ## Tag and push a beta pre-release — GitHub Actions will create the pre-release
	@set -e; \
	if [ -n "$$(git status --porcelain)" ]; then echo "error: working tree not clean"; exit 1; fi; \
	VERSION=$$(./asimov --version); \
	BETA_NUM=1; \
	while git tag | grep -q "^v$$VERSION-beta\.$$BETA_NUM$$"; do \
	  BETA_NUM=$$((BETA_NUM + 1)); \
	done; \
	TAG="v$$VERSION-beta.$$BETA_NUM"; \
	echo "Tagging $$TAG (signed)..."; \
	git tag -s "$$TAG" -m "Pre-release $$TAG"; \
	git push $(RELEASE_REMOTE) "$$TAG"; \
	echo "Tag $$TAG pushed — GitHub Actions will create the pre-release."

bump-formula: ## Update the Homebrew tap formula to match the current asimov version (TAP_DIR=../homebrew-tap)
	@set -eo pipefail; \
	if [ ! -d "$(TAP_DIR)/Formula" ]; then echo "error: $(TAP_DIR)/Formula not found — clone django23/homebrew-tap to $(TAP_DIR)"; exit 1; fi; \
	VERSION=$$(./asimov --version); \
	TAG="v$$VERSION"; \
	URL="https://github.com/$(REPO)/archive/refs/tags/$$TAG.tar.gz"; \
	echo "Fetching $$URL ..."; \
	TARBALL=$$(mktemp); \
	trap 'rm -f "$$TARBALL"' EXIT; \
	if ! curl -fsSL "$$URL" -o "$$TARBALL"; then echo "error: download failed for $$URL (is the release published?)"; exit 1; fi; \
	if [ ! -s "$$TARBALL" ]; then echo "error: downloaded tarball is empty — refusing to compute a hash"; exit 1; fi; \
	SHA=$$(shasum -a 256 "$$TARBALL" | awk '{print $$1}'); \
	EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"; \
	if [ -z "$$SHA" ] || [ "$$SHA" = "$$EMPTY_SHA" ] || [ "$$SHA" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then echo "error: refusing empty/zero sha256 (download likely failed; is the release published?)"; exit 1; fi; \
	echo "sha256: $$SHA"; \
	FORMULA="$(TAP_DIR)/Formula/asimov.rb"; \
	/usr/bin/sed -i '' -E "s|url \"https://github.com/django23/asimov/archive/refs/tags/v[^\"]+\"|url \"$$URL\"|" "$$FORMULA"; \
	/usr/bin/sed -i '' -E "s|sha256 \"[a-f0-9]{64}\"|sha256 \"$$SHA\"|" "$$FORMULA"; \
	/usr/bin/sed -i '' -E "s|version \"[^\"]+\"|version \"$$VERSION\"|" "$$FORMULA"; \
	echo "Updated $$FORMULA"; \
	( cd "$(TAP_DIR)" && git diff --stat Formula/asimov.rb; \
	  git add Formula/asimov.rb && \
	  git commit -S -m "asimov $$VERSION" && \
	  echo "Review the commit in $(TAP_DIR), then: cd $(TAP_DIR) && git push" )

ship-formula: ## Wait for release.yml to finish, then bump-formula and push the tap
	@set -e; \
	echo "Waiting 15s for GitHub to register the release.yml run..."; \
	sleep 15; \
	RUN_ID=$$(gh run list --workflow=release.yml --limit=1 --json databaseId -q '.[0].databaseId'); \
	if [ -z "$$RUN_ID" ]; then echo "error: no release.yml runs found — did 'make release' push the tag?"; exit 1; fi; \
	echo "Watching run $$RUN_ID..."; \
	gh run watch "$$RUN_ID" --exit-status; \
	$(MAKE) bump-formula; \
	echo "Pushing tap..."; \
	( cd "$(TAP_DIR)" && git push ); \
	echo "✓ Formula updated and pushed."

verify-release: ## brew upgrade asimov and print the installed version
	@set -e; \
	brew update; \
	brew upgrade asimov || brew install django23/tap/asimov; \
	"$$(brew --prefix asimov)/bin/asimov" --version
