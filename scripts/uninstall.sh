#!/usr/bin/env bash

# Uninstall Asimov.
#
# @author  Steve Grunwell
# @license MIT

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/vars"

printf '\n\033[0;36mRemoving command %s\033[0m\n' "${BIN}"
[[ -f ${BIN} ]] && rm "${BIN}"

# Remove the legacy fork agent too (label renamed django23 -> stevegrunwell in v0.9.0).
if launchctl list | grep -q com.django23.asimov; then
  launchctl remove com.django23.asimov 2>/dev/null || true
fi

if launchctl list | grep -q "${PLIST%.plist}"; then
  printf '\n\033[0;36mUnloading current instance of %s\033[0m\n' "${PLIST}"
  launchctl unload "${DIR}/${PLIST}"
fi

printf '\n\033[0;32mAsimov has been successfully uninstalled.\033[0m\n'
