#!/usr/bin/env bash
# shellcheck shell=bash
#
# Data entities. Each of the three record types Asimov works with lives in a
# tab-separated file under $ASIMOV_DATA and is loaded here into parallel arrays.
#
#   sentinel    a directory to exclude, plus the file that must sit next to it
#   fixed dir   a global tool cache, always excluded, no sentinel
#   skip path   a directory never descended into
#
# Parallel arrays rather than associative ones: macOS ships bash 3.2, which has
# no `declare -A`. Index i of every array in a group describes the same record.
#
# Arrays are assigned at file scope, not inside the loaders, because under bash
# 3.2 an array assigned inside a function with `local`/`declare` semantics would
# not survive the call.

ASIMOV_SENTINEL_DIR=()
ASIMOV_SENTINEL_FILE=()
ASIMOV_SENTINEL_ECOSYSTEM=()
ASIMOV_FIXED_DIRS=()
ASIMOV_FIXED_DIR_TOOL=()
ASIMOV_SKIP_PATHS=()

# Abort with a clear message when a data file is missing. A data file that
# vanished means a broken install, not a recoverable condition.
require_data_file() {
    [[ -r "$1" ]] && return 0
    echo "asimov: missing data file: $1" >&2
    echo "  This install is incomplete. Reinstall asimov, or set ASIMOV_DATA to the data directory." >&2
    exit 1
}

# Load data/sentinels.tsv into ASIMOV_SENTINEL_*.
load_sentinels() {
    local file="${ASIMOV_DATA}/sentinels.tsv"
    require_data_file "$file"

    local dir sentinel ecosystem
    while IFS=$'\t' read -r dir sentinel ecosystem _ || [[ -n "$dir" ]]; do
        [[ -z "$dir" || "$dir" == '#'* ]] && continue
        if [[ -z "$sentinel" ]]; then
            echo "asimov: ${file}: entry '${dir}' has no sentinel, skipping" >&2
            continue
        fi
        ASIMOV_SENTINEL_DIR+=("$dir")
        ASIMOV_SENTINEL_FILE+=("$sentinel")
        ASIMOV_SENTINEL_ECOSYSTEM+=("${ecosystem:-unknown}")
    done < "$file"
}

# Load data/fixed-dirs.tsv into ASIMOV_FIXED_DIRS (absolute) and ASIMOV_FIXED_DIR_TOOL.
# Paths in the file are relative to the root; the root prefix is applied here so
# the file never has to mention ~ or a username.
load_fixed_dirs() {
    local file="${ASIMOV_DATA}/fixed-dirs.tsv"
    require_data_file "$file"

    local path tool
    while IFS=$'\t' read -r path tool _ || [[ -n "$path" ]]; do
        [[ -z "$path" || "$path" == '#'* ]] && continue
        ASIMOV_FIXED_DIRS+=("${ASIMOV_ROOT}/${path}")
        ASIMOV_FIXED_DIR_TOOL+=("${tool:-unknown}")
    done < "$file"
}

# Load data/skip-paths.tsv into ASIMOV_SKIP_PATHS (absolute), then append the
# paths named under [skip_paths] in the config. Both the find expression and the
# Spotlight top-up read this one array, so they cannot drift apart.
load_skip_paths() {
    local file="${ASIMOV_DATA}/skip-paths.tsv"
    require_data_file "$file"

    local path
    while IFS=$'\t' read -r path _ || [[ -n "$path" ]]; do
        [[ -z "$path" || "$path" == '#'* ]] && continue
        ASIMOV_SKIP_PATHS+=("${ASIMOV_ROOT}/${path}")
    done < "$file"

    for path in ${ASIMOV_CONFIG_EXTRA_SKIP_PATHS[@]+"${ASIMOV_CONFIG_EXTRA_SKIP_PATHS[@]}"}; do
        ASIMOV_SKIP_PATHS+=("$path")
    done
}

# Every sentinel record in effect for this run, one "dir sentinel" pair per line:
# the built-in list minus anything the config disables, plus anything it adds.
#
# The pair string is the unit the config speaks in, so a `sentinels.disabled`
# entry is matched against the whole "dir sentinel" string.
sentinel_active_pairs() {
    local i pair dpair disabled

    for (( i = 0; i < ${#ASIMOV_SENTINEL_DIR[@]}; i++ )); do
        pair="${ASIMOV_SENTINEL_DIR[$i]} ${ASIMOV_SENTINEL_FILE[$i]}"
        disabled=false
        for dpair in ${ASIMOV_CONFIG_DISABLED_SENTINELS[@]+"${ASIMOV_CONFIG_DISABLED_SENTINELS[@]}"}; do
            [[ "$pair" == "$dpair" ]] && { disabled=true; break; }
        done
        [[ "$disabled" == true ]] && continue
        printf '%s\n' "$pair"
    done

    for pair in ${ASIMOV_CONFIG_EXTRA_SENTINELS[@]+"${ASIMOV_CONFIG_EXTRA_SENTINELS[@]}"}; do
        printf '%s\n' "$pair"
    done
}

# Load every data file. Requires ASIMOV_ROOT, so it runs after init_root_paths.
load_data() {
    load_sentinels
    load_fixed_dirs
    load_skip_paths
}
