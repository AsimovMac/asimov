#!/usr/bin/env bash

# Install Asimov as a launchd daemon.
#
# @author  Steve Grunwell
# @license MIT

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/vars"

# Verify that Asimov is executable.
chmod +x "${DIR}/asimov"

# Copy Asimov into /usr/local/bin.
printf '\033[0;36mInstalling to %s\033[0m\n' "${BIN}"
cp -a "${DIR}/asimov" "${BIN}"

if [[ "${NAME}" != "asimov" ]]; then
  printf '\n\033[0;32mInstalled as %s (skipping launchd — plist targets the default name).\033[0m\n' "${BIN}"
  exit 0
fi

# Migrate: remove the legacy fork agent (label renamed django23 -> stevegrunwell in v0.10.0).
if launchctl list | grep -q com.django23.asimov; then
  printf '\n\033[0;36mRemoving legacy com.django23.asimov agent\033[0m\n'
  launchctl remove com.django23.asimov 2>/dev/null || true
fi

# Ensure daemon is not already loaded.
if launchctl list | grep -q "${PLIST%.plist}"; then
  printf '\n\033[0;36mUnloading current instance of %s\033[0m\n' "${PLIST}"
  launchctl unload "${DIR}/${PLIST}"
fi

# Load the .plist file.
launchctl load "${DIR}/${PLIST}" && printf '\n\033[0;32mAsimov daemon has been loaded!\033[0m\n'

# Run Asimov for the first time.
printf '\nRun Asimov immediately with \033[0;35m%s\033[0m\n' "${BIN}"
