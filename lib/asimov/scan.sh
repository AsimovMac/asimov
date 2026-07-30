#!/usr/bin/env bash
# shellcheck shell=bash
#
# What to scan, and the `find` expression used to scan it.

# Resolve the set of directories to scan into ASIMOV_SCAN_DIRS.
#   - A positional CLI argument overrides everything: scan only that directory.
#   - Otherwise scan the home directory plus any [scan] extra dirs from config.
# Configured dirs that don't exist are warned about and skipped rather than
# aborting the run (e.g. an unmounted external volume).
resolve_scan_dirs() {
    ASIMOV_SCAN_DIRS=()

    if [[ -n "$ASIMOV_SCAN_DIR" ]]; then
        if [[ ! -d "$ASIMOV_SCAN_DIR" ]]; then
            echo "asimov: not a directory: ${ASIMOV_SCAN_DIR}" >&2
            exit 1
        fi
        ASIMOV_SCAN_DIRS=("$ASIMOV_SCAN_DIR")
        return 0
    fi

    ASIMOV_SCAN_DIRS=("$ASIMOV_ROOT")
    local scan_dir
    for scan_dir in ${ASIMOV_CONFIG_SCAN_DIRS[@]+"${ASIMOV_CONFIG_SCAN_DIRS[@]}"}; do
        if [[ ! -d "$scan_dir" ]]; then
            [[ -z "$ASIMOV_QUIET" ]] && \
                echo "asimov: configured scan directory does not exist, skipping: ${scan_dir}" >&2
            continue
        fi
        ASIMOV_SCAN_DIRS+=("$scan_dir")
    done

    prune_nested_scan_dirs
}

# Drop any scan dir that equals or nests inside another (Time Machine exclusions
# and find traversal are both recursive, so the parent already covers it). This
# also collapses exact duplicates, e.g. a configured ~/Projects under $HOME.
prune_nested_scan_dirs() {
    local -a kept=()
    local dir other nested dup k
    for dir in "${ASIMOV_SCAN_DIRS[@]}"; do
        nested=false
        for other in "${ASIMOV_SCAN_DIRS[@]}"; do
            [[ "$dir" == "$other" ]] && continue
            if [[ "$dir" == "$other"/* ]]; then nested=true; break; fi
        done
        [[ "$nested" == true ]] && continue
        dup=false
        for k in ${kept[@]+"${kept[@]}"}; do
            [[ "$k" == "$dir" ]] && { dup=true; break; }
        done
        [[ "$dup" == true ]] && continue
        kept+=("$dir")
    done
    ASIMOV_SCAN_DIRS=("${kept[@]}")
}

# Build find parameters to skip ASIMOV_SKIP_PATHS (.Trash, Library).
# Already-excluded paths are NOT pruned here — they are filtered cheaply via grep in
# exclude_paths_from_stdin instead, avoiding the O(dirs × prune_count) performance trap.
# Result is stored in global find_parameters_skip.
build_find_skip_params() {
    find_parameters_skip=()
    local skip_dir
    for skip_dir in "${ASIMOV_SKIP_PATHS[@]}"; do
        find_parameters_skip+=( -not \( -path "${skip_dir}" -prune \) )
    done
}

# Build the find clause matching one directory/sentinel pair, appending it to
# find_parameters_vendor.
#
# A glob sentinel is handed to `sh -c` as a positional arg ($1), never
# interpolated into the script body, so a crafted sentinel (from the data file or
# from user config) cannot inject shell commands. $1 is intentionally unquoted so
# the inner sh glob-expands the pattern; its value is never re-parsed as shell code.
append_find_vendor_clause() {
    local dir_name="$1" sentinel_name="$2"
    local -a sentinel_check

    if [[ "$sentinel_name" == *'*'* ]]; then
        # shellcheck disable=SC2016,SC2086
        sentinel_check=( -execdir sh -c 'ls -d -- $1 >/dev/null 2>&1' _ "${sentinel_name}" \; )
    else
        sentinel_check=( -execdir test -e "${sentinel_name}" \; )
    fi

    find_parameters_vendor+=( -or \( \
        -type d \
        -name "${dir_name}" \
        "${sentinel_check[@]}" \
        -prune \
        -print \
    \) )
}

# Build find parameters for every active directory/sentinel pair.
# Result is stored in global find_parameters_vendor.
build_find_vendor_params() {
    find_parameters_vendor=()
    local pair parts
    while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        read -ra parts <<< "$pair"
        append_find_vendor_clause "${parts[0]}" "${parts[1]}"
    done < <(sentinel_active_pairs)
}
