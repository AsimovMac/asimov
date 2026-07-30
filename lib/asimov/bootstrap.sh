#!/usr/bin/env bash
# shellcheck shell=bash
#
# Runtime setup shared by every command: colours, size constants, temp files,
# and resolution of the root directory and the state-file paths hanging off it.
#
# Sourced by bin/asimov before any other module. Defines functions and scalar
# constants only; nothing here runs work.

# Named constants for size formatting.
readonly ASIMOV_KB_PER_MB=1024
readonly ASIMOV_KB_PER_GB=1048576

# Disable colours when stdout is not a terminal (e.g. launchd, pipes, redirects).
if [[ -t 1 ]]; then
    readonly ASIMOV_COLOR_INFO=$'\033[0;36m'
    readonly ASIMOV_COLOR_SUCCESS=$'\033[0;32m'
    readonly ASIMOV_COLOR_DIM=$'\033[0;90m'
    readonly ASIMOV_COLOR_RESET=$'\033[0m'
else
    readonly ASIMOV_COLOR_INFO=''
    readonly ASIMOV_COLOR_SUCCESS=''
    readonly ASIMOV_COLOR_DIM=''
    readonly ASIMOV_COLOR_RESET=''
fi

# Time Machine's system preferences, home of the "sticky" path exclusion list
# (tmutil addexclusion -p). Overridable so tests can point at a fixture.
readonly ASIMOV_TM_PLIST="${ASIMOV_TM_PLIST:-/Library/Preferences/com.apple.TimeMachine.plist}"

# Print a dim timestamped debug line when --verbose is set.
# Uses bash's built-in $SECONDS variable (auto-increments from 0 at script start).
# Output goes to stderr so it stays visible even when stdout is redirected
# (e.g. inside discover_new_paths_via_mdfind whose stdout is captured to a file).
verbose_timing() {
    [[ -n "$ASIMOV_VERBOSE" ]] || return 0
    printf '%s  [%ds] %s%s\n' "$ASIMOV_COLOR_DIM" "$SECONDS" "$1" "$ASIMOV_COLOR_RESET" >&2
}

# Resolve the root directory to scan (console user's home when running as root).
resolve_asimov_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        local console_user
        console_user="$(stat -f '%Su' /dev/console 2>/dev/null || echo '')"
        if [[ -n "$console_user" && "$console_user" != "root" ]]; then
            local root_dir
            root_dir="$(dscl . -read "/Users/${console_user}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
            if [[ -n "$root_dir" ]]; then
                echo "$root_dir"
                return
            fi
        fi
        echo ~
    else
        echo ~
    fi
}

# Create the temp files used to track excluded sizes and pre-existing exclusions,
# and arrange for them to be removed on exit. Called once, before any command runs.
#
# Temp files hold the full home-directory layout, so the umask in bin/asimov keeps
# them private (0600/0700).
init_temp_files() {
    ASIMOV_SIZE_LOG="$(mktemp)"
    ASIMOV_EXCLUDED_CACHE="$(mktemp)"
    ASIMOV_PATH_CACHE_TMP=""
    trap 'rm -f "$ASIMOV_SIZE_LOG" "$ASIMOV_EXCLUDED_CACHE" "$ASIMOV_PATH_CACHE_TMP"' EXIT
}

# Resolve ASIMOV_ROOT and every path derived from it.
#
# Scalars only: `readonly ARRAY=(...)` inside a function is *local* under bash 3.2
# (the version macOS ships) and global under bash 5, so arrays are assigned by the
# data loaders at file scope instead.
init_root_paths() {
    ASIMOV_ROOT="$(resolve_asimov_root)"
    readonly ASIMOV_ROOT
    readonly ASIMOV_CACHE_DIR="${ASIMOV_ROOT}/.cache/asimov"
    readonly ASIMOV_EXCLUDED_STATE="${ASIMOV_CACHE_DIR}/excluded"
    readonly ASIMOV_FAILED_STATE="${ASIMOV_CACHE_DIR}/failed"
    readonly ASIMOV_MDFIND_SEEN="${ASIMOV_CACHE_DIR}/mdfind_seen"
    readonly ASIMOV_PATH_CACHE="${ASIMOV_CACHE_DIR}/paths"
    readonly ASIMOV_CONFIG_FILE="${ASIMOV_ROOT}/.config/asimov/config"
}
