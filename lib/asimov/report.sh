#!/usr/bin/env bash
# shellcheck shell=bash
#
# Everything the user reads: usage text, size formatting, run summary.

print_usage() {
    printf 'Usage: asimov [--dry-run] [--verbose] [--quiet] [--stats] [--no-read-cache] [--no-write-cache] [directory]\n'
    printf '       asimov prune [--quiet]\n'
    printf '       asimov doctor [--quiet]\n'
    printf '\n'
    printf 'Exclude development dependency directories from Time Machine backups.\n'
    printf '\n'
    printf 'Commands:\n'
    printf '  prune              Report Time Machine exclusions whose directory no longer\n'
    printf '                     exists, and compact Asimov'\''s own cache. Read-only:\n'
    printf '                     it prints the removal command rather than running it\n'
    printf '  doctor             Check this install for problems: a shadowed binary, a\n'
    printf '                     leftover schedule, an unreadable cache, a bad config.\n'
    printf '                     Read-only; exits 1 if it finds anything\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --dry-run          Print what would be excluded without changing Time Machine\n'
    printf '  --verbose          Show all directories including already-excluded ones\n'
    printf '  --quiet            Suppress all output except errors\n'
    printf '  --stats            Show directory sizes and total space in the summary\n'
    printf '  --no-read-cache    Ignore cached state; re-discover and re-verify everything (rebuilds the cache)\n'
    printf '  --no-write-cache   Run normally but do not persist any cache updates\n'
    printf '  --full-scan        Alias for --no-read-cache\n'
    printf '  --no-cache         Alias for --no-read-cache --no-write-cache (fully stateless run)\n'
    printf '  --help             Show this help and exit\n'
    printf '  --version          Show version and exit\n'
    printf '\n'
    printf 'Arguments:\n'
    printf '  directory          Directory to scan (default: home directory)\n'
    printf '\n'
    printf 'To scan additional directories on every run, add them to the config file\n'
    printf '(~/.config/asimov/config) under a [scan] section:\n'
    printf '\n'
    printf '  [scan]\n'
    printf '  extra = /private/var/www\n'
}

# Format a size in KB as human-readable string (e.g. 1.2G, 500M, 42K).
format_size_kb() {
    local kb="$1"
    if [[ "$kb" -ge ASIMOV_KB_PER_GB ]]; then
        local whole=$((kb / ASIMOV_KB_PER_GB))
        local frac=$(( (kb % ASIMOV_KB_PER_GB) * 10 / ASIMOV_KB_PER_GB ))
        printf '%s.%sG' "$whole" "$frac"
    elif [[ "$kb" -ge ASIMOV_KB_PER_MB ]]; then
        local whole=$((kb / ASIMOV_KB_PER_MB))
        local frac=$(( (kb % ASIMOV_KB_PER_MB) * 10 / ASIMOV_KB_PER_MB ))
        printf '%s.%sM' "$whole" "$frac"
    else
        printf '%sK' "$kb"
    fi
}

# Print summary of excluded (or would-exclude) count, and total size when --stats is set.
print_exclusion_summary() {
    local excluded_count msg
    excluded_count=$(wc -l < "$ASIMOV_SIZE_LOG" | tr -d ' ')

    if [[ "$excluded_count" -eq 0 ]]; then
        if [[ -n "$ASIMOV_DRY_RUN" ]]; then
            msg="No directories would be excluded."
        else
            msg="✓ Done! No new directories to exclude."
        fi
    else
        local verb
        if [[ -n "$ASIMOV_DRY_RUN" ]]; then
            verb="Would exclude"
        else
            verb="✓ Done! Excluded"
        fi
        if [[ -n "$ASIMOV_STATS" ]]; then
            local total_kb total_human
            total_kb=$(awk '{s+=$1} END {print s}' "$ASIMOV_SIZE_LOG")
            total_human="$(format_size_kb "$total_kb")"
            msg="${verb} ${excluded_count} directories, totalling ${total_human}."
        else
            msg="${verb} ${excluded_count} directories."
        fi
    fi

    printf '\n%s%s%s\n' "$ASIMOV_COLOR_SUCCESS" "$msg" "$ASIMOV_COLOR_RESET"
}
