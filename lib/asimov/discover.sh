#!/usr/bin/env bash
# shellcheck shell=bash
#
# Incremental discovery via Spotlight, used on a cached run instead of a full
# `find` traversal.

# Discover new dependency paths via Spotlight (mdfind) that aren't in the current
# cache. For each candidate, validate that the sentinel exists in the parent
# directory. Outputs newly discovered paths to stdout.
discover_new_paths_via_mdfind() {
    local cached_paths_file="$1"

    # Resolve the active sentinel pairs once, not per candidate, and collect the
    # distinct directory names they match on for the Spotlight query.
    local -a active_sentinels=() dir_names=()
    local pair parts dir_name seen=""
    while IFS= read -r pair; do
        [[ -n "$pair" ]] || continue
        active_sentinels+=("$pair")
        read -ra parts <<< "$pair"
        dir_name="${parts[0]}"
        if [[ " $seen " != *" $dir_name "* ]]; then
            dir_names+=("$dir_name")
            seen="$seen $dir_name"
        fi
    done < <(sentinel_active_pairs)

    [[ ${#dir_names[@]} -eq 0 ]] && return 0

    # Build mdfind query: kMDItemContentType == "public.folder" && (name == "x" || ...)
    local name_clauses=""
    for dir_name in "${dir_names[@]}"; do
        [[ -n "$name_clauses" ]] && name_clauses="${name_clauses} || "
        name_clauses="${name_clauses}kMDItemFSName == \"${dir_name}\""
    done
    local query="kMDItemContentType == \"public.folder\" && (${name_clauses})"

    # Run mdfind, write results to temp file (avoids slow printf on 15K-line strings).
    verbose_timing "Running Spotlight query for ${#dir_names[@]} directory names…"
    local candidates_file uncached_file
    candidates_file="$(mktemp)"
    uncached_file="$(mktemp)"
    local scan_dir
    for scan_dir in "${ASIMOV_SCAN_DIRS[@]}"; do
        mdfind -onlyin "$scan_dir" "$query" 2>/dev/null >> "$candidates_file" || true
    done
    if [[ ! -s "$candidates_file" ]]; then
        rm -f "$candidates_file" "$uncached_file"
        return 0
    fi

    local total_mdfind
    total_mdfind="$(wc -l < "$candidates_file" | tr -d ' ')"
    verbose_timing "Spotlight returned ${total_mdfind} candidates"

    # Descendant filter first: skip candidates nested under cached paths. TM exclusions
    # are recursive so descendants are already covered. Run this BEFORE the exact-match
    # filter because it's fast (grep -Fvf ~4s on 15K lines) and eliminates ~90% of
    # candidates, making the subsequent exact filter much cheaper.
    if [[ -n "$cached_paths_file" && -s "$cached_paths_file" ]]; then
        local prefix_file
        prefix_file="$(mktemp)"
        sed 's|$|/|' "$cached_paths_file" > "$prefix_file"
        grep -Fvf "$prefix_file" "$candidates_file" > "$uncached_file" || true
        rm -f "$prefix_file"
    else
        cp "$candidates_file" "$uncached_file"
    fi
    rm -f "$candidates_file"

    if [[ ! -s "$uncached_file" ]]; then
        verbose_timing "All ${total_mdfind} candidates were nested under cached paths"
        rm -f "$uncached_file"
        return 0
    fi
    local uncached_count
    uncached_count="$(wc -l < "$uncached_file" | tr -d ' ')"
    verbose_timing "After descendant filter: ${uncached_count} remain (skipped $((total_mdfind - uncached_count)) nested)"

    # Exact-match filter: remove candidates already in the path cache or previously
    # checked by mdfind (no-sentinel directories that would just be rechecked for nothing).
    # Uses sort+comm for set difference — BSD grep -Fxvf is O(n×m) and takes 35s on 15K
    # lines; sort+comm is O(n log n) and handles the same in <1s.
    local combined_filter
    combined_filter="$(mktemp)"
    {
        if [[ -n "$cached_paths_file" && -s "$cached_paths_file" ]]; then cat "$cached_paths_file"; fi
        if cache_readable "$ASIMOV_MDFIND_SEEN"; then cat "$ASIMOV_MDFIND_SEEN"; fi
    } > "$combined_filter"
    if [[ -s "$combined_filter" ]]; then
        local sorted_candidates sorted_filter filtered_file
        sorted_candidates="$(mktemp)"
        sorted_filter="$(mktemp)"
        filtered_file="$(mktemp)"
        sort "$uncached_file" > "$sorted_candidates"
        sort -u "$combined_filter" > "$sorted_filter"
        comm -23 "$sorted_candidates" "$sorted_filter" > "$filtered_file"
        rm -f "$sorted_candidates" "$sorted_filter"
        mv -f "$filtered_file" "$uncached_file"
    fi
    rm -f "$combined_filter"

    if [[ ! -s "$uncached_file" ]]; then
        verbose_timing "All candidates already checked"
        rm -f "$uncached_file"
        return 0
    fi
    local filtered_count
    filtered_count="$(wc -l < "$uncached_file" | tr -d ' ')"
    verbose_timing "After cache filter: ${filtered_count} new candidates to check (skipped $((uncached_count - filtered_count)) seen)"

    local candidate mdfind_checked=0 mdfind_matched=0
    while IFS= read -r candidate; do
        [[ -d "$candidate" ]] || continue

        # Skip paths under ASIMOV_SKIP_PATHS
        local skip=false
        local skip_dir
        for skip_dir in "${ASIMOV_SKIP_PATHS[@]}"; do
            if [[ "$candidate" == "${skip_dir}"/* || "$candidate" == "${skip_dir}" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == true ]] && continue

        # Bash builtins instead of dirname/basename subprocesses
        local parent_dir="${candidate%/*}"
        local candidate_basename="${candidate##*/}"
        local sentinel_found=false

        for pair in "${active_sentinels[@]}"; do
            read -ra parts <<< "$pair"
            [[ "${parts[0]}" == "$candidate_basename" ]] || continue
            local sentinel_name="${parts[1]}"
            if [[ "$sentinel_name" == *'*'* ]]; then
                # shellcheck disable=SC2086
                if (cd "$parent_dir" && ls -d $sentinel_name) >/dev/null 2>&1; then
                    sentinel_found=true
                    break
                fi
            else
                if [[ -e "${parent_dir}/${sentinel_name}" ]]; then
                    sentinel_found=true
                    break
                fi
            fi
        done

        mdfind_checked=$((mdfind_checked + 1))
        if [[ "$sentinel_found" == true ]]; then
            mdfind_matched=$((mdfind_matched + 1))
            printf '%s\n' "$candidate"
        fi
        if [[ $((mdfind_checked % 100)) -eq 0 ]]; then
            verbose_timing "  …checked ${mdfind_checked} candidates (${mdfind_matched} matched)"
        fi
    done < "$uncached_file"

    # Persist all checked candidates so they're skipped on the next cached run.
    # Prevents re-checking 1000+ no-sentinel candidates every time.
    # No-op for dry-run/no-cache (no persistent state should be written).
    if [[ -z "$ASIMOV_DRY_RUN" && -z "$ASIMOV_NO_WRITE_CACHE" ]]; then
        ensure_cache_dir
        if cache_writable "$ASIMOV_MDFIND_SEEN"; then
            cat "$uncached_file" >> "$ASIMOV_MDFIND_SEEN"
        fi
    fi
    rm -f "$uncached_file"
    verbose_timing "Spotlight: checked ${mdfind_checked} candidates, ${mdfind_matched} new matches"
}
