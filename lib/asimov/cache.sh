#!/usr/bin/env bash
# shellcheck shell=bash
#
# Asimov's own state under ~/.cache/asimov: the discovered-path cache, the
# excluded/failed state files, and the mdfind_seen list.
#
# Every cache file is an optimisation: a run must survive one being unreadable
# or unwritable rather than aborting. Without the guards below a bare `cat` on an
# unreadable state file fails under `set -Eeu -o pipefail` and kills the whole
# run, printing nothing but "Permission denied" (see issue #122).
#
# The usual cause is a run as root — `sudo asimov`, or a schedule installed as
# root — leaving root-owned files behind for the next run as the user.

ASIMOV_CACHE_WARNED=

# Warn once per run that the cache is unusable, and name the fix. Always goes to
# stderr, including under --quiet: this is a degraded run, not routine chatter.
warn_unusable_cache() {
    [[ -n "$ASIMOV_CACHE_WARNED" ]] && return 0
    ASIMOV_CACHE_WARNED=1
    printf '! %s is not %s — continuing without the cache.\n' "$1" "$2" >&2
    printf '  This usually means a previous run as root left root-owned files behind.\n' >&2
    printf '  To reset it:\n\n    rm -rf %s\n\n' "$ASIMOV_CACHE_DIR" >&2
    return 0
}

# True when a state file exists and can be read. A missing file is not an error
# (there is simply nothing cached yet), so it returns false without warning.
cache_readable() {
    [[ -f "$1" ]] || return 1
    [[ -r "$1" ]] && return 0
    warn_unusable_cache "$1" "readable"
    return 1
}

# True when a state file can be written to, creating it if necessary. An absent
# file is writable when its directory is.
cache_writable() {
    if [[ -e "$1" ]]; then
        [[ -w "$1" ]] && return 0
        warn_unusable_cache "$1" "writable"
        return 1
    fi
    [[ -d "$ASIMOV_CACHE_DIR" && -w "$ASIMOV_CACHE_DIR" ]] && return 0
    [[ -d "$ASIMOV_CACHE_DIR" ]] || return 1   # not created yet; ensure_cache_dir reports
    warn_unusable_cache "$ASIMOV_CACHE_DIR" "writable"
    return 1
}

# Append a line to a state file, skipping silently when it isn't writable.
# Always returns 0 so callers can use it as the tail of an && list under set -e.
append_state() {
    cache_writable "$2" || return 0
    printf '%s\n' "$1" >> "$2" 2>/dev/null || true
    return 0
}

# Create the cache directory, chown to console user when running as root.
ensure_cache_dir() {
    if [[ ! -d "$ASIMOV_CACHE_DIR" ]]; then
        mkdir -p "$ASIMOV_CACHE_DIR" 2>/dev/null || {
            warn_unusable_cache "$ASIMOV_CACHE_DIR" "writable"
            return 0
        }
    fi
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        local console_user
        console_user="$(stat -f '%Su' /dev/console 2>/dev/null || echo '')"
        if [[ -n "$console_user" && "$console_user" != "root" ]]; then
            # Create the state files *before* the chown. Appending to an existing
            # file never changes its owner, so every write later in this root run
            # lands in a file the console user can still read next time. Chowning
            # only the directory (as this did before) left root-owned files behind
            # that broke the following user run outright — issue #122.
            touch "$ASIMOV_EXCLUDED_STATE" "$ASIMOV_FAILED_STATE" \
                  "$ASIMOV_MDFIND_SEEN" "$ASIMOV_PATH_CACHE" 2>/dev/null || true
            chown -R "$console_user" "$ASIMOV_CACHE_DIR" 2>/dev/null || true
        fi
    fi
    return 0
}

# Read cached paths, filtering to those that still exist as directories
# and fall under one of the scan dirs. Outputs valid paths to stdout.
read_path_cache() {
    cache_readable "$ASIMOV_PATH_CACHE" || return 0
    local line d in_scope
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^#  ]] && continue
        [[ -z "$line" ]] && continue
        # Must still exist as a directory
        [[ -d "$line" ]] || continue
        # Must be under one of the scan dirs
        in_scope=false
        for d in "${ASIMOV_SCAN_DIRS[@]}"; do
            if [[ "$line" == "${d}"/* || "$line" == "${d}" ]]; then in_scope=true; break; fi
        done
        [[ "$in_scope" == true ]] || continue
        printf '%s\n' "$line"
    done < "$ASIMOV_PATH_CACHE"
}

# Initialize the path cache file with a header, truncating any old contents.
# No-op if --dry-run or writes are disabled (--no-write-cache / --no-cache).
init_path_cache() {
    [[ -n "$ASIMOV_DRY_RUN" || -n "$ASIMOV_NO_WRITE_CACHE" ]] && return 0
    ensure_cache_dir
    cache_writable "$ASIMOV_PATH_CACHE" || return 0
    printf '# asimov path cache — updated %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$ASIMOV_PATH_CACHE"
}

# Append a single path to the cache file. No-op if --dry-run or writes are disabled (--no-write-cache / --no-cache).
append_path_to_cache() {
    [[ -n "$ASIMOV_DRY_RUN" || -n "$ASIMOV_NO_WRITE_CACHE" ]] && return 0
    append_state "$1" "$ASIMOV_PATH_CACHE"
}

# Remove paths that are descendants of other paths in the list.
# Expects sorted input. Outputs only outermost (non-nested) paths.
# Example: /a/node_modules and /a/node_modules/foo/node_modules → keeps only /a/node_modules
# (Time Machine exclusions are recursive, so the descendant is already covered.)
dedup_nested_paths() {
    local last_kept="" path
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ -n "$last_kept" && "$path" == "${last_kept}/"* ]]; then
            continue
        fi
        printf '%s\n' "$path"
        last_kept="$path"
    done
}

# Sort, deduplicate, and prune stale entries from the cache file.
# Writes atomically via temp file + mv. No-op if --dry-run or writes are disabled (--no-write-cache / --no-cache).
finalize_path_cache() {
    [[ -n "$ASIMOV_DRY_RUN" || -n "$ASIMOV_NO_WRITE_CACHE" ]] && return 0
    cache_readable "$ASIMOV_PATH_CACHE" || return 0
    cache_writable "$ASIMOV_PATH_CACHE" || return 0

    ASIMOV_PATH_CACHE_TMP="${ASIMOV_PATH_CACHE}.tmp.$$"
    {
        printf '# asimov path cache — updated %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        # Keep only lines that are existing directories, sorted and deduplicated
        while IFS= read -r line; do
            [[ "$line" =~ ^# ]] && continue
            [[ -z "$line" ]] && continue
            if [[ -d "$line" ]]; then
                printf '%s\n' "$line"
            fi
        done < "$ASIMOV_PATH_CACHE" | sort -u | dedup_nested_paths
    } > "$ASIMOV_PATH_CACHE_TMP"
    mv -f "$ASIMOV_PATH_CACHE_TMP" "$ASIMOV_PATH_CACHE"
    ASIMOV_PATH_CACHE_TMP=""

    # Dedup the mdfind_seen file (grows with appends each run)
    if cache_readable "$ASIMOV_MDFIND_SEEN" && cache_writable "$ASIMOV_MDFIND_SEEN"; then
        sort -u "$ASIMOV_MDFIND_SEEN" > "${ASIMOV_MDFIND_SEEN}.tmp"
        mv -f "${ASIMOV_MDFIND_SEEN}.tmp" "$ASIMOV_MDFIND_SEEN"
    fi

    # Dedup the failed-state file (grows with appends each run)
    if cache_readable "$ASIMOV_FAILED_STATE" && cache_writable "$ASIMOV_FAILED_STATE"; then
        sort -u "$ASIMOV_FAILED_STATE" > "${ASIMOV_FAILED_STATE}.tmp"
        mv -f "${ASIMOV_FAILED_STATE}.tmp" "$ASIMOV_FAILED_STATE"
    fi

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        local console_user
        console_user="$(stat -f '%Su' /dev/console 2>/dev/null || echo '')"
        if [[ -n "$console_user" && "$console_user" != "root" ]]; then
            chown "$console_user" "$ASIMOV_PATH_CACHE" 2>/dev/null || true
        fi
    fi
}

# Drop entries whose directory no longer exists from Asimov's path cache.
# Echoes the number of entries removed. This only ever touches Asimov's own
# file under ~/.cache/asimov.
prune_path_cache() {
    cache_readable "$ASIMOV_PATH_CACHE" || { echo 0; return 0; }
    cache_writable "$ASIMOV_PATH_CACHE" || { echo 0; return 0; }

    # A brace group with a redirect runs in the current shell, so the counters
    # below survive the loop.
    local tmp line dropped=0
    tmp="${ASIMOV_PATH_CACHE}.tmp.$$"
    {
        printf '# asimov path cache — updated %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        while IFS= read -r line; do
            [[ "$line" =~ ^# ]] && continue
            [[ -z "$line" ]] && continue
            if [[ -d "$line" ]]; then
                printf '%s\n' "$line"
            else
                dropped=$((dropped + 1))
            fi
        done < "$ASIMOV_PATH_CACHE"
    } > "$tmp"

    mv -f "$tmp" "$ASIMOV_PATH_CACHE"
    echo "$dropped"
}

# Build the cache of paths already excluded from Time Machine, in
# $ASIMOV_EXCLUDED_CACHE. Merges the Spotlight index (what macOS reports) with
# Asimov's own persistent state (written after each successful tmutil call).
# The persistent state covers:
#   - Interrupted runs (Ctrl+C before all tmutil calls complete)
#   - Spotlight indexing delays (tmutil set the xattr but Spotlight hasn't indexed it)
build_excluded_cache() {
    verbose_timing "Building excluded-path cache via Spotlight…"
    : > "$ASIMOV_EXCLUDED_CACHE"

    local scan_dir spotlight_count
    for scan_dir in "${ASIMOV_SCAN_DIRS[@]}"; do
        mdfind -onlyin "$scan_dir" "com_apple_backup_excludeItem = 'com.apple.backupd'" 2>/dev/null \
            >> "$ASIMOV_EXCLUDED_CACHE" || true
    done
    sort -u -o "$ASIMOV_EXCLUDED_CACHE" "$ASIMOV_EXCLUDED_CACHE"
    spotlight_count="$(wc -l < "$ASIMOV_EXCLUDED_CACHE" | tr -d ' ')"

    # Failed paths (e.g. read-only dirs inside Go's module cache) are merged in too,
    # so the bulk filter skips them instantly instead of wasting time retrying tmutil.
    # Skipped under --no-read-cache (--full-scan / --no-cache): every path is then
    # re-verified against the tmutil isexcluded ground truth instead.
    if [[ -z "$ASIMOV_NO_READ_CACHE" ]] && { cache_readable "$ASIMOV_EXCLUDED_STATE" || cache_readable "$ASIMOV_FAILED_STATE"; }; then
        {
            cat "$ASIMOV_EXCLUDED_CACHE"
            if cache_readable "$ASIMOV_EXCLUDED_STATE"; then cat "$ASIMOV_EXCLUDED_STATE"; fi
            if cache_readable "$ASIMOV_FAILED_STATE"; then cat "$ASIMOV_FAILED_STATE"; fi
        } | sort -u > "${ASIMOV_EXCLUDED_CACHE}.merged"
        mv -f "${ASIMOV_EXCLUDED_CACHE}.merged" "$ASIMOV_EXCLUDED_CACHE"
    fi
    verbose_timing "Excluded-path cache ready ($(wc -l < "$ASIMOV_EXCLUDED_CACHE" | tr -d ' ') entries, ${spotlight_count} from Spotlight)"
}
