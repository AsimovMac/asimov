#!/usr/bin/env bash
#
# Install asimov from GitHub without cloning the repo.
# Installs to ~/.local/bin and sets up a daily launchd schedule.
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
BIN_DIR="${HOME}/.local/bin"
PLIST_LABEL="com.stevegrunwell.asimov"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${PLIST_DIR}/${PLIST_LABEL}.plist"

printf '\033[0;36mInstalling asimov...\033[0m\n'

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$PLIST_DIR"

# Download the script
curl -fsSL "${BASE_URL}/asimov" -o "${BIN_DIR}/asimov"
chmod +x "${BIN_DIR}/asimov"

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
printf 'Uninstall: %s/asimov-uninstall (coming soon) or:\n' "$BIN_DIR"
printf '  rm "%s/asimov"\n' "$BIN_DIR"
printf '  launchctl unload "%s"\n' "$PLIST_FILE"
printf '  rm "%s"\n' "$PLIST_FILE"
