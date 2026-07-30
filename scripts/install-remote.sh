#!/usr/bin/env bash
#
# Install asimov from GitHub without cloning the repo.
# Installs to ~/.local and sets up a daily launchd schedule.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AsimovMac/asimov/main/scripts/install-remote.sh | bash
#
# Install a specific ref (e.g. a beta tag) — fetch the installer AND the files
# it downloads from the same ref:
#   curl -fsSL https://raw.githubusercontent.com/AsimovMac/asimov/v0.9.0-beta.1/scripts/install-remote.sh \
#     | ASIMOV_REF=v0.9.0-beta.1 bash

set -euo pipefail

REPO="${ASIMOV_REPO:-AsimovMac/asimov}"
REF="${ASIMOV_REF:-main}"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${REF}"
TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/${REF}"
PREFIX="${HOME}/.local"
BIN_DIR="${PREFIX}/bin"
LIBEXEC_DIR="${PREFIX}/libexec/asimov"
SHARE_DIR="${PREFIX}/share/asimov"
PLIST_LABEL="com.stevegrunwell.asimov"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${PLIST_DIR}/${PLIST_LABEL}.plist"

printf '\033[0;36mInstalling asimov...\033[0m\n'

mkdir -p "$BIN_DIR" "$LIBEXEC_DIR" "$SHARE_DIR" "$PLIST_DIR"

# Asimov is a launcher plus a library and data files, so this fetches the whole
# tree rather than a single script. All three land under one prefix: the launcher
# locates the other two by walking up from its own physical path.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

curl -fsSL "$TARBALL_URL" | tar -xzf - -C "$workdir"
src="$(find "$workdir" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ -z "$src" || ! -f "${src}/bin/asimov" ]]; then
    echo "asimov: downloaded archive does not look like an asimov checkout" >&2
    exit 1
fi

install -m 0755 "${src}/bin/asimov" "${BIN_DIR}/asimov"
# Clear the old library and data first: a module or data file dropped in a later
# release must not survive as a stale leftover.
rm -rf "${LIBEXEC_DIR:?}" "${SHARE_DIR:?}"
mkdir -p "$LIBEXEC_DIR" "$SHARE_DIR"
cp -a "${src}/lib/asimov/." "${LIBEXEC_DIR}/"
cp -a "${src}/data/." "${SHARE_DIR}/"

# Download and patch the plist (rewrite Program path)
curl -fsSL "${BASE_URL}/${PLIST_LABEL}.plist" | \
    sed "s|/usr/local/bin/asimov|${BIN_DIR}/asimov|" > "$PLIST_FILE"

# Migrate: remove the legacy fork agent (label renamed django23 -> stevegrunwell in v0.10.0)
if launchctl list 2>/dev/null | grep -q com.django23.asimov; then
    launchctl remove com.django23.asimov 2>/dev/null || true
fi

# Unload existing daemon if present
if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
fi

# Load the daemon
launchctl load "$PLIST_FILE"

printf '\n\033[0;32mInstalled!\033[0m\n'
printf '  Binary: %s/asimov\n' "$BIN_DIR"
printf '  Library: %s\n' "$LIBEXEC_DIR"
printf '  Data: %s\n' "$SHARE_DIR"
printf '  Schedule: daily (launchd)\n'
printf '\n'

# Check if ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$BIN_DIR"; then
    printf '\033[0;33mNote:\033[0m %s is not in your PATH.\n' "$BIN_DIR"
    printf 'Add this to your shell profile (~/.zshrc or ~/.bashrc):\n'
    # shellcheck disable=SC2016
    printf '\n  export PATH="%s:$PATH"\n\n' "$BIN_DIR"
fi

printf 'Run now: %s/asimov\n' "$BIN_DIR"
printf 'Uninstall:\n'
printf '  rm "%s/asimov"\n' "$BIN_DIR"
printf '  rm -rf "%s" "%s"\n' "$LIBEXEC_DIR" "$SHARE_DIR"
printf '  launchctl unload "%s"\n' "$PLIST_FILE"
printf '  rm "%s"\n' "$PLIST_FILE"
