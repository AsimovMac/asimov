#!/usr/bin/env bash
# shellcheck shell=bash
#
# Argument parsing, the scan command, and the top-level dispatch.

# Parse options into ASIMOV_*. Handles --help and --version by exiting directly.
# Unknown options exit 1.
parse_args() {
    ASIMOV_DRY_RUN=
    ASIMOV_VERBOSE=
    ASIMOV_QUIET=
    ASIMOV_STATS=
    ASIMOV_NO_READ_CACHE=
    ASIMOV_NO_WRITE_CACHE=
    ASIMOV_SCAN_DIR=
    ASIMOV_COMMAND=scan

    # Subcommands are recognised only as the first argument, so that a directory
    # sharing the name stays reachable as `asimov ./prune`.
    case "${1:-}" in
        prune)  ASIMOV_COMMAND=prune;  shift ;;
        doctor) ASIMOV_COMMAND=doctor; shift ;;
    esac

    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run)    ASIMOV_DRY_RUN=1 ;;
            --verbose)    ASIMOV_VERBOSE=1 ;;
            --quiet)      ASIMOV_QUIET=1 ;;
            --stats)      ASIMOV_STATS=1 ;;
            # Cache controls along two axes. --full-scan and --no-cache are kept as
            # back-compat aliases: --full-scan = --no-read-cache; --no-cache = both.
            --no-read-cache)  ASIMOV_NO_READ_CACHE=1 ;;
            --no-write-cache) ASIMOV_NO_WRITE_CACHE=1 ;;
            --full-scan)  ASIMOV_NO_READ_CACHE=1 ;;
            --no-cache)   ASIMOV_NO_READ_CACHE=1; ASIMOV_NO_WRITE_CACHE=1 ;;
            --help)       print_usage; exit 0 ;;
            --version)    printf '%s\n' "$ASIMOV_VERSION"; exit 0 ;;
            -*)
                echo "asimov: unknown option '$arg'" >&2
                print_usage >&2
                exit 1
                ;;
            *)
                ASIMOV_SCAN_DIR="$arg"
                ;;
        esac
    done

    if [[ -n "$ASIMOV_QUIET" && -n "$ASIMOV_VERBOSE" ]]; then
        echo "asimov: --quiet and --verbose are mutually exclusive" >&2
        exit 1
    fi
}

# The default command: find dependency directories and exclude them.
cmd_scan() {
    if [[ ! -d "$ASIMOV_ROOT" ]]; then
        echo "asimov: root directory does not exist or is not a directory: $ASIMOV_ROOT" >&2
        exit 1
    fi

    load_data
    resolve_scan_dirs

    # When ignoring cached reads but still writing (e.g. --full-scan / --no-read-cache),
    # clear the append-only state so the rebuilt cache reflects only this run's results.
    # When not writing (--no-cache / --no-write-cache), leave every cache file untouched.
    # (The paths cache is truncated separately by init_path_cache before the full scan.)
    if [[ -n "$ASIMOV_NO_READ_CACHE" && -z "$ASIMOV_NO_WRITE_CACHE" ]]; then
        rm -f "$ASIMOV_EXCLUDED_STATE" "$ASIMOV_FAILED_STATE" "$ASIMOV_MDFIND_SEEN" 2>/dev/null || true
    fi

    build_excluded_cache

    # Cache is read when the cache file exists and reads aren't disabled
    # (--no-read-cache / --full-scan / --no-cache force a full scan).
    if [[ -z "$ASIMOV_NO_READ_CACHE" ]] && cache_readable "$ASIMOV_PATH_CACHE"; then
        scan_from_cache
    else
        scan_full
    fi

    # Built-in fixed dirs are opt-in via config; extra fixed dirs are always
    # processed, because the user asked for them by name.
    if [[ "$ASIMOV_CONFIG_FIXED_DIRS_ENABLED" == "true" ]]; then
        exclude_existing_dirs '💾 Excluding known cache directories…' "${ASIMOV_FIXED_DIRS[@]}"
    fi
    if [[ ${#ASIMOV_CONFIG_EXTRA_FIXED_DIRS[@]} -gt 0 ]]; then
        exclude_existing_dirs '⚙️  Excluding user-configured directories…' \
            "${ASIMOV_CONFIG_EXTRA_FIXED_DIRS[@]}"
    fi

    verbose_timing "All exclusions processed"
    [[ -z "$ASIMOV_QUIET" ]] && print_exclusion_summary
    return 0
}

# Cached run: exclude everything already known, then top up via Spotlight.
scan_from_cache() {
    [[ -z "$ASIMOV_QUIET" ]] && printf '\n%s⏳ Using cached paths…%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"

    # Read cache, filter stale/out-of-scope paths, collect valid ones
    local cached_valid new_paths deduped total_before total_after path
    cached_valid="$(mktemp)"
    read_path_cache > "$cached_valid"
    verbose_timing "Cache read: $(wc -l < "$cached_valid" | tr -d ' ') valid paths"

    [[ -z "$ASIMOV_QUIET" ]] && printf '%s🔍 Checking for new projects via Spotlight…%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"
    new_paths="$(mktemp)"
    discover_new_paths_via_mdfind "$cached_valid" > "$new_paths"
    verbose_timing "Spotlight discovery: $(wc -l < "$new_paths" | tr -d ' ') new paths"

    # Exclude all paths (cached + new), deduped to remove nested redundancies.
    # Time Machine exclusions are recursive, so excluding a parent covers descendants.
    [[ -z "$ASIMOV_QUIET" ]] && printf '%s📦 Processing matches…%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"
    deduped="$(mktemp)"
    { cat "$cached_valid"; cat "$new_paths"; } | sort -u | dedup_nested_paths > "$deduped"
    total_before=$(( $(wc -l < "$cached_valid" | tr -d ' ') + $(wc -l < "$new_paths" | tr -d ' ') ))
    total_after=$(wc -l < "$deduped" | tr -d ' ')
    verbose_timing "Dedup: ${total_before} paths → ${total_after} (removed $((total_before - total_after)) nested)"
    exclude_paths_from_stdin < "$deduped"
    rm -f "$deduped"

    # Update cache: append new discoveries to existing cache, then sort/dedup/prune
    while IFS= read -r path; do
        append_path_to_cache "$path"
    done < "$new_paths"
    finalize_path_cache
    verbose_timing "Cache finalized"

    rm -f "$cached_valid" "$new_paths"
}

# Full run: traverse the scan dirs with find.
scan_full() {
    [[ -z "$ASIMOV_QUIET" ]] && printf '\n%s⏳ Scanning for dependency directories…%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"

    build_find_skip_params
    build_find_vendor_params
    verbose_timing "Find parameters built"

    [[ -z "$ASIMOV_QUIET" ]] && printf '%s📦 Processing matches…%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"

    # Stream find output: tee writes to cache incrementally, pipe feeds exclusion.
    # On interrupt, tee has already appended every path find emitted, so the
    # next run can use the partial cache.
    verbose_timing "Starting find traversal of ${ASIMOV_SCAN_DIRS[*]}…"
    # The tee'd branch is only safe when the cache is actually writable: a failing
    # tee takes the whole pipeline down under pipefail. Fall back to the plain
    # pipeline otherwise, so an unusable cache costs speed, not the run (#122).
    if [[ -z "$ASIMOV_DRY_RUN" && -z "$ASIMOV_NO_WRITE_CACHE" ]] \
        && { ensure_cache_dir; cache_writable "$ASIMOV_PATH_CACHE"; }; then
        init_path_cache
        { find "${ASIMOV_SCAN_DIRS[@]}" \( "${find_parameters_skip[@]}" \) \( -false "${find_parameters_vendor[@]}" \) \
            || true; } | tee -a "$ASIMOV_PATH_CACHE" | exclude_paths_from_stdin
        verbose_timing "Find + exclude complete"
        finalize_path_cache
        verbose_timing "Cache finalized"
    else
        { find "${ASIMOV_SCAN_DIRS[@]}" \( "${find_parameters_skip[@]}" \) \( -false "${find_parameters_vendor[@]}" \) \
            || true; } | exclude_paths_from_stdin
        verbose_timing "Find + exclude complete"
    fi
}

# Entry point. bin/asimov calls this with the full argument list.
asimov_main() {
    parse_args "$@"
    init_temp_files
    init_root_paths
    load_config

    case "$ASIMOV_COMMAND" in
        prune)  cmd_prune;  exit 0 ;;
        doctor) cmd_doctor; exit $? ;;
        scan)   cmd_scan;   exit 0 ;;
    esac
}
