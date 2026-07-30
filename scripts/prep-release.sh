#!/usr/bin/env bash
#
# prep-release.sh — Prepare a release PR.
#
# Bumps ASIMOV_VERSION in `bin/asimov`, promotes [Unreleased] in CHANGELOG.md to
# a new version section (with compare links), runs `make check`, then
# branches and commits. Does NOT push or open the PR — review first.
#
# Usage: scripts/prep-release.sh X.Y.Z
#    or: VERSION=X.Y.Z scripts/prep-release.sh

set -euo pipefail

VERSION="${1:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
    printf 'usage: %s X.Y.Z\n' "$0" >&2
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'error: version must be semver X.Y.Z (got: %s)\n' "$VERSION" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    printf 'error: working tree not clean\n' >&2
    exit 1
fi

PREV="$(./bin/asimov --version)"
if [[ "$PREV" == "$VERSION" ]]; then
    printf 'error: ASIMOV_VERSION is already %s\n' "$VERSION" >&2
    exit 1
fi

BRANCH="release/$VERSION"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    printf 'error: branch %s already exists\n' "$BRANCH" >&2
    exit 1
fi

DATE="$(date +%Y-%m-%d)"
printf 'Preparing release %s (previous: %s, date: %s)\n' "$VERSION" "$PREV" "$DATE"

git checkout -b "$BRANCH"

# Bump ASIMOV_VERSION in the launcher.
/usr/bin/sed -i '' -E "s/^readonly ASIMOV_VERSION='[^']+'/readonly ASIMOV_VERSION='$VERSION'/" bin/asimov

# Promote [Unreleased] to a new version section, insert a fresh empty
# [Unreleased] above, and add a compare-link entry.
awk -v ver="$VERSION" -v prev="$PREV" -v date="$DATE" '
/^## \[Unreleased\]$/ && !promoted {
    print "## [Unreleased]"
    print ""
    print "### Added"
    print ""
    print "### Changed"
    print ""
    print "### Fixed"
    print ""
    print "### Removed"
    print ""
    print "## [" ver "] — " date
    promoted = 1
    next
}
/^\[Unreleased\]: / && !link_updated {
    print "[Unreleased]: https://github.com/AsimovMac/asimov/compare/v" ver "...main"
    print "[" ver "]: https://github.com/AsimovMac/asimov/compare/v" prev "...v" ver
    link_updated = 1
    next
}
{ print }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

printf '\n=== diff ===\n'
git --no-pager diff --stat bin/asimov CHANGELOG.md

printf '\nRunning make check...\n'
make check

git add bin/asimov CHANGELOG.md
git commit -S -m "docs: release $VERSION"

cat <<EOF

✓ Release $VERSION prepared on branch $BRANCH

Next steps:
  git push -u origin $BRANCH
  gh pr create --base main --fill --title "docs: release $VERSION"
  # …after CI is green and the PR is merged:
  gh pr merge <PR#> --squash --delete-branch
  git checkout main && git pull --ff-only
  make release
  make ship-formula
  make verify-release
EOF
