#!/usr/bin/env bash
# shellcheck shell=bash
#
# The `prune` subcommand.
#
# Asimov's own exclusions cannot go stale. `tmutil addexclusion PATH` stores the
# exclusion as an extended attribute on the directory itself, so deleting the
# directory deletes the exclusion with it.
#
# What *does* go stale is the "sticky" list: `tmutil addexclusion -p PATH` records
# the path in Time Machine's system preferences instead, and that entry survives
# the directory forever. Asimov has never written to that list, but other tools
# and manual commands do, and nothing surfaces the leftovers.

# Resolve a "~user/…" path, as stored in Time Machine's preferences, to an
# absolute one. Falls back to /Users/<name> when the account can't be read.
expand_tm_path() {
    local path="$1" user rest home
    case "$path" in
        '~'*) ;;
        *) printf '%s\n' "$path"; return 0 ;;
    esac
    path="${path#\~}"
    user="${path%%/*}"
    rest="${path#"$user"}"
    if [[ -z "$user" ]]; then
        printf '%s\n' "${ASIMOV_ROOT}${rest}"
        return 0
    fi
    home="$(dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
    [[ -n "$home" ]] || home="/Users/${user}"
    printf '%s\n' "${home}${rest}"
}

# Print the sticky exclusion list, one raw path per line.
# `defaults` renders it as a plist array; strip the parentheses, indentation,
# trailing commas, and surrounding quotes.
read_sticky_exclusions() {
    [[ -r "$ASIMOV_TM_PLIST" ]] || return 0
    defaults read "${ASIMOV_TM_PLIST%.plist}" SkipPaths 2>/dev/null \
        | sed -e '/^[[:space:]]*[()]/d' \
              -e 's/^[[:space:]]*//' \
              -e 's/[[:space:]]*,$//' \
              -e 's/^"//' -e 's/"$//' \
        | grep -v '^$' || true
}

cmd_prune() {
    local raw expanded sticky_total=0
    local stale_paths="" stale_count=0

    while IFS= read -r raw; do
        sticky_total=$((sticky_total + 1))
        expanded="$(expand_tm_path "$raw")"
        if [[ ! -e "$expanded" ]]; then
            stale_count=$((stale_count + 1))
            stale_paths="${stale_paths}${raw}"$'\n'
        fi
    done < <(read_sticky_exclusions)

    local cache_dropped
    cache_dropped="$(prune_path_cache)"

    [[ -n "$ASIMOV_QUIET" ]] && return 0

    if [[ "$stale_count" -gt 0 ]]; then
        printf '\n%sStale Time Machine exclusions (%s):%s\n' \
            "$ASIMOV_COLOR_INFO" "$stale_count" "$ASIMOV_COLOR_RESET"
        printf '%s' "$stale_paths" | while IFS= read -r raw; do
            [[ -z "$raw" ]] && continue
            printf '  %s %spath no longer exists%s\n' \
                "$raw" "$ASIMOV_COLOR_DIM" "$ASIMOV_COLOR_RESET"
        done
        printf '\nThese are sticky exclusions (%stmutil addexclusion -p%s), which Asimov never sets.\n' \
            "$ASIMOV_COLOR_DIM" "$ASIMOV_COLOR_RESET"
        printf 'They persist after the directory is deleted. To remove one:\n\n'
        printf '  sudo tmutil removeexclusion -p %s\n\n' "$(printf '%s' "$stale_paths" | head -1)"
    elif [[ "$sticky_total" -gt 0 ]]; then
        printf '\n%s✓%s No stale exclusions. All %s sticky entries point at directories that exist.\n' \
            "$ASIMOV_COLOR_SUCCESS" "$ASIMOV_COLOR_RESET" "$sticky_total"
    else
        printf '\n%s✓%s No sticky Time Machine exclusions are set on this Mac.\n' \
            "$ASIMOV_COLOR_SUCCESS" "$ASIMOV_COLOR_RESET"
    fi

    if [[ "$cache_dropped" -gt 0 ]]; then
        printf 'Asimov cache: %s stale %s dropped.\n' \
            "$cache_dropped" "$([[ "$cache_dropped" -eq 1 ]] && echo entry || echo entries)"
    else
        printf 'Asimov cache: nothing to prune.\n'
    fi

    printf '\n%sAsimov'\''s own exclusions are stored on the directory itself, so they are\nremoved automatically when you delete it — only sticky entries can outlive it.%s\n' \
        "$ASIMOV_COLOR_DIM" "$ASIMOV_COLOR_RESET"
}
