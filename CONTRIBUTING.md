# Contributing to Asimov

Thanks for your interest in contributing! Asimov is a small, focused project and contributions of all sizes are welcome.

## Getting started

**Prerequisites:** macOS with [Homebrew](https://brew.sh) installed.

```sh
git clone https://github.com/AsimovMac/asimov.git
cd asimov
brew install bats-core shellcheck
```

Verify everything works:

```sh
make check
```

## Development workflow

| Command | What it does |
|---|---|
| `make help` | List available make targets with descriptions |
| `make test` | Run the [Bats](https://github.com/bats-core/bats-core) test suite |
| `make test-system-bash` | Run the suite under the macOS system bash (3.2) |
| `make lint` | Run [ShellCheck](https://www.shellcheck.net/) on all shell scripts |
| `make check` | Run both tests and linting |
| `make version` | Print asimov version |
| `make exclusions` | List all paths excluded from Time Machine (requires sudo) |

To run a single test by name: `bats tests/behavior.bats --filter "substring of test name"` or `bats tests/sentinels.bats --filter "npm"`.

### Which bash your tests run under

`asimov` starts with `#!/usr/bin/env bash`, so it runs under whichever `bash` comes first on `PATH`. On macOS that is one of two very different things:

- `/bin/bash`, the system bash, still **3.2** because Apple froze it at the last GPLv2 release. This is what most users get.
- A **5.x** build from Homebrew, which is probably what *you* get.

They disagree on array and IFS semantics, so a change can pass locally and fail for users. Before opening a PR touching shell logic, run:

```sh
make test-system-bash        # or: make test BASH_BIN=/bin/bash
```

CI runs the full matrix (both macOS versions × both bash versions) on every PR, so it will catch this either way, but the local target is faster than a round trip.

Tests can also run concurrently, which needs GNU parallel:

```sh
brew install parallel
make test BATS_JOBS=4
```

The main script supports `--help`, `--version`, `--dry-run`, `--verbose`, and `--quiet`; unknown options exit with an error.

## Adding a new dependency pattern

This is the most common type of contribution. To add a new ecosystem or dependency directory:

1. **Add the sentinel pair** to the `ASIMOV_VENDOR_DIR_SENTINELS` array in [`asimov`](asimov) — one `'directory sentinel'` entry per pattern.
2. **Add a test** in [`tests/sentinels.bats`](tests/sentinels.bats) using `create_project` to build the fixture. Keep this file in sync with `ASIMOV_VENDOR_DIR_SENTINELS` (one test per sentinel pair).
3. **Run `make check`** to verify your changes pass tests and linting.
4. **Add a changelog entry** under the `[Unreleased]` section in [`CHANGELOG.md`](CHANGELOG.md).

**Example sentinel entry:**

```bash
'.zig-cache build.zig'   # Zig build cache
```

This means: exclude `.zig-cache/` only when `build.zig` exists in the same directory.

## Commit conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Format your commits as:

```
type(scope): short description
```

**Types:** `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `build`, `ci`

**Examples:**

- `feat(sentinels): add Zig build cache exclusion`
- `fix: prevent duplicate exclusions on re-run`
- `test: add coverage for Go modules`
- `docs: update installation instructions`

## Pull requests

- Branch from `main` (the default branch).
- Keep PRs focused — one feature or fix per PR.
- Ensure `make check` passes before submitting.
- Update `CHANGELOG.md` for user-facing changes.

## Code style

- Bash/shell: **2-space indentation**, LF line endings, UTF-8.
- Enforced via [EditorConfig](.editorconfig) — most editors pick this up automatically.

## Project structure

```
asimov                  # Main bash script
tests/
  sentinels.bats        # Tests for each dependency pattern
  behavior.bats         # Tests for edge cases and general behavior
  format.bats           # Unit tests for format_size_kb()
  root_guard.bats       # Tests for the sudo/root guard and styled diagnostics
  plist.bats            # Tests for the LaunchAgent plist
  test_helper.bash      # Shared setup/teardown and assertions
  bin/tmutil            # Mock tmutil for testing
  bin/mdfind            # Mock mdfind for testing
scripts/
  install.sh            # Local installation script
  install-remote.sh     # Curl-based remote installer
  uninstall.sh          # Uninstallation script
Makefile                # Build targets (test, lint, check, install, uninstall)
```

## Releasing (maintainers)

**The pipeline, end to end:**

1. **Develop** on a branch → **PR into `main`**. CI (macOS 14 + 15) must pass; commits must be signed.
2. **Merge** to `main`.
3. **`make release`** tags `vX.Y.Z` (signed) → GitHub Actions publishes the release + `asimov` binary.
4. **Homebrew** autobumps `brew install asimov` on its own (~3h later). Nothing to do.

Version = SemVer: new feature → **minor**, bug fix → **patch**. Pre-releases: `make release-beta` (GitHub pre-release; Homebrew ignores it). Details below.

`main` is protected: signed commits + PR required + both CI checks (`test (macos-14)`, `test (macos-15)`) must pass. The flow below respects all of that.

### One-time setup

Install signing keys (see [SSH-signed commits](#ssh-signed-commits-one-time-per-clone) below) in this clone — tags and commits must be signed.

### Per-release flow

```sh
make prep-release VERSION=X.Y.Z              # branch, bump version, promote CHANGELOG, run check, commit
git push -u origin release/X.Y.Z
gh pr create --base main --fill --title "docs: release X.Y.Z"
gh pr checks <PR#> --watch --fail-fast

# After the PR is merged:
gh pr merge <PR#> --squash --delete-branch
git checkout main && git pull --ff-only

make release                                 # signed tag + push (Actions publishes the GitHub release)
```

**Homebrew is homebrew-core, and it updates itself.** `asimov` is on Homebrew's autobump list, so BrewTestBot opens the version-bump PR automatically (~3h after a GitHub release) — there is **nothing to do** for a normal version release. Attempting `brew bump-formula-pr` for a version will fail with an autobump-exclusion error.

Only *metadata* changes (homepage, url org, license) need a manual PR against [homebrew-core](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/a/asimov.rb) — edit the formula, `brew style Formula/a/asimov.rb`, then open the PR. The old `django23/homebrew-tap` is archived and no longer used.

If `gh pr create` fails with `Head sha can't be blank` (GraphQL indexing lag), retry once or fall back to the REST API:

```sh
gh api repos/AsimovMac/asimov/pulls -X POST \
  -f title="docs: release X.Y.Z" \
  -f head="release/X.Y.Z" -f base="main" \
  -f body="See CHANGELOG.md"
```

### Beta releases

Skip `prep-release` (no CHANGELOG promotion needed). Run `make release-beta` from any branch — it auto-increments the `-beta.N` suffix and marks the GitHub release as pre-release. Homebrew ignores pre-releases, so there's nothing else to do.

### If something goes wrong

**Tag already exists (duplicate from an earlier attempt).** Delete remote tag + release, prune locally, re-run:

```sh
gh release delete vX.Y.Z --yes --cleanup-tag
git fetch --prune --prune-tags origin
git tag -d vX.Y.Z 2>/dev/null || true
make release                                  # re-tags from current main
```

**CI fails on the release PR.** Fix locally, push to the PR branch, re-run `gh pr checks <PR#> --watch`. Don't merge until green.

**You merged the PR but `make release` aborts with "working tree not clean".** Run `git status` — you likely have a stray local file. `git stash` it and retry.

**`make prep-release` fails with "working tree not clean" but the dirty files ARE the release.** `prep-release` assumes the version bump comes first and the substantive changes follow. If your work is already uncommitted, do it manually: branch (`git checkout -b release/X.Y.Z`), commit your changes, then bump `ASIMOV_VERSION` in `asimov` and run the awk block from `scripts/prep-release.sh` against `CHANGELOG.md` to promote `[Unreleased]` and add the compare links. Run `make check`, commit, push, open the PR.

### SSH-signed commits (one-time per clone)

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing -N ""
gh auth refresh -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/id_ed25519_signing.pub --type signing --title "$(hostname)"

git config user.email "$(gh api user --jq '.id')+$(gh api user --jq '.login')@users.noreply.github.com"
git config gpg.format ssh
git config user.signingkey ~/.ssh/id_ed25519_signing.pub
git config commit.gpgsign true
git config tag.gpgsign true

mkdir -p ~/.config/git
echo "$(git config user.email) $(awk '{print $1, $2}' ~/.ssh/id_ed25519_signing.pub)" >> ~/.config/git/allowed_signers
git config gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

## Questions?

Open an [issue](https://github.com/AsimovMac/asimov/issues) — happy to help.
