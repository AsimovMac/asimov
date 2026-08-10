#!/usr/bin/env bash
# shellcheck shell=bash
#
# The `doctor` subcommand.
#
# Diagnoses an install rather than changing it. The failure modes it looks for
# are the ones people hit coming from v0.3.0 (issue #122): an old binary still
# first on PATH, a LaunchAgent pointing at a Homebrew cellar that no longer
# exists, and a cache left root-owned by a run as root.
#
# Two rules keep it safe to run at any point in a migration:
#   - It never writes anything. Fixes are printed, never applied.
#   - It never executes another asimov binary it finds. v0.3.0 parses no
#     arguments at all, so running it to ask its version would start a real
#     scan; versions are read out of the file instead.

# The label a current install schedules itself under. Everything else in the
# list below is a leftover to be removed, never re-loaded.
readonly ASIMOV_CURRENT_LABEL='com.stevegrunwell.asimov'

# Every known LaunchAgent label Asimov has ever shipped under, plus Homebrew's.
readonly ASIMOV_DOCTOR_LABELS=(
    'com.stevegrunwell.asimov'   # current, and the original
    'com.django23.asimov'        # the v0.4.x–v0.8.0 fork
    'homebrew.mxcl.asimov'       # brew services
)

ASIMOV_DOCTOR_PROBLEMS=0

doctor_heading() {
    [[ -n "$ASIMOV_QUIET" ]] && return 0
    printf '\n%s%s%s\n' "$ASIMOV_COLOR_INFO" "$1" "$ASIMOV_COLOR_RESET"
    return 0
}

doctor_ok() {
    [[ -n "$ASIMOV_QUIET" ]] && return 0
    printf '  %s✓%s %s\n' "$ASIMOV_COLOR_SUCCESS" "$ASIMOV_COLOR_RESET" "$1"
    return 0
}

doctor_note() {
    [[ -n "$ASIMOV_QUIET" ]] && return 0
    printf '  %s·%s %s\n' "$ASIMOV_COLOR_DIM" "$ASIMOV_COLOR_RESET" "$1"
    return 0
}

# Problems print even under --quiet: a silent doctor that found something is
# worse than useless in a cron job.
doctor_problem() {
    ASIMOV_DOCTOR_PROBLEMS=$((ASIMOV_DOCTOR_PROBLEMS + 1))
    printf '  ✗ %s\n' "$1"
    return 0
}

# Print a command the user can copy to fix the problem just reported.
doctor_fix() {
    printf '      %s%s%s\n' "$ASIMOV_COLOR_DIM" "$1" "$ASIMOV_COLOR_RESET"
    return 0
}

# Resolve a path to its physical location, symlinks and all. Homebrew installs
# asimov as a symlink into the cellar, so comparing raw paths would report a
# shadow that isn't there.
doctor_realpath() {
    local path="$1" dir base
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || { printf '%s\n' "$path"; return 0; }
    base="$(basename "$path")"
    while [[ -L "${dir}/${base}" ]]; do
        local target
        target="$(readlink "${dir}/${base}")"
        case "$target" in
            /*) dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
            *)  dir="$(cd "$dir" && cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || break ;;
        esac
        base="$(basename "$target")"
    done
    printf '%s/%s\n' "$dir" "$base"
}

# Read a version out of an asimov script without running it. Handles the current
# `readonly ASIMOV_VERSION='x'` (in bin/asimov), the same line in a pre-0.12
# single-file install, and v0.3.0's `# @version x` header.
doctor_file_version() {
    local file="$1" line
    line="$(grep -m1 -E "^readonly ASIMOV_VERSION=|^# @version " "$file" 2>/dev/null || true)"
    [[ -n "$line" ]] || { printf 'unknown\n'; return 0; }
    line="${line##*@version }"
    line="${line##*=}"
    line="${line//\'/}"
    line="${line//\"/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    printf '%s\n' "${line:-unknown}"
}

# Every `asimov` on PATH, in PATH order, deduplicated by physical path.
doctor_path_binaries() {
    local dir candidate resolved seen=""
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        candidate="${dir}/asimov"
        [[ -x "$candidate" && ! -d "$candidate" ]] || continue
        resolved="$(doctor_realpath "$candidate")"
        case "$seen" in
            *"|${resolved}|"*) continue ;;
        esac
        seen="${seen}|${resolved}|"
        printf '%s\n' "$resolved"
    done < <(printf '%s\n' "${PATH//:/$'\n'}")
}

doctor_check_install() {
    doctor_heading 'Install'

    local running
    running="$(doctor_realpath "$ASIMOV_SELF")"
    doctor_ok "asimov ${ASIMOV_VERSION} (${running})"

    local -a found=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && found+=("$line")
    done < <(doctor_path_binaries)

    if [[ ${#found[@]} -eq 0 ]]; then
        doctor_note "no asimov on PATH — you are running it by path"
        return 0
    fi

    local first="${found[0]}"
    if [[ "$first" != "$running" ]]; then
        doctor_problem "typing 'asimov' runs a different binary — this one is shadowed"
        doctor_fix "${first}  (version $(doctor_file_version "$first"))"
        doctor_fix "Remove the one you don't want, or fix the order of PATH."
    else
        doctor_ok "'asimov' on PATH is this one"
    fi

    local other
    for other in "${found[@]}"; do
        [[ "$other" == "$first" ]] && continue
        doctor_note "also installed: ${other} (version $(doctor_file_version "$other"))"
    done
    return 0
}

doctor_check_schedule() {
    doctor_heading 'Schedule'

    local agents_dir="${ASIMOV_ROOT}/Library/LaunchAgents"
    local label plist program active=0

    for label in "${ASIMOV_DOCTOR_LABELS[@]}"; do
        plist="${agents_dir}/${label}.plist"
        [[ -f "$plist" ]] || continue
        active=$((active + 1))

        program="$(plutil -extract Program raw "$plist" 2>/dev/null || true)"
        if [[ -n "$program" && ! -x "$program" ]]; then
            doctor_problem "${label}: its program ${program} no longer exists"
            doctor_fix "launchctl bootout gui/\$(id -u)/${label}"
            doctor_fix "rm ${plist}"
            continue
        fi

        if launchctl list "$label" >/dev/null 2>&1; then
            doctor_ok "${label} — loaded, runs daily"
        elif [[ "$label" == "$ASIMOV_CURRENT_LABEL" ]]; then
            doctor_problem "${label}: installed but not loaded, so it never runs"
            doctor_fix "launchctl bootstrap gui/\$(id -u) ${plist}"
        else
            # A label we no longer ship, sitting unloaded: a leftover from an
            # older install. Loading it is never the right advice.
            doctor_problem "${label}: leftover from an older install, not loaded"
            doctor_fix "rm ${plist}"
        fi
    done

    if [[ "$active" -eq 0 ]]; then
        doctor_note "not scheduled — Asimov only runs when you run it"
    elif [[ "$active" -gt 1 ]]; then
        doctor_problem "more than one schedule is installed (${active}) — they will both run"
        doctor_fix "Keep com.stevegrunwell.asimov and bootout the rest."
    fi
    return 0
}

# Humanise an age in seconds: "3 minutes ago", "2 days ago".
doctor_humanise_age() {
    local seconds="$1" value unit
    if   [[ "$seconds" -lt 60 ]];    then printf 'just now\n'; return 0
    elif [[ "$seconds" -lt 3600 ]];  then value=$((seconds / 60));    unit=minute
    elif [[ "$seconds" -lt 86400 ]]; then value=$((seconds / 3600));  unit=hour
    else                                  value=$((seconds / 86400)); unit=day
    fi
    printf '%s %s%s ago\n' "$value" "$unit" "$([[ "$value" -eq 1 ]] || echo s)"
}

doctor_check_cache() {
    doctor_heading 'Cache'

    if [[ ! -d "$ASIMOV_CACHE_DIR" ]]; then
        doctor_ok "no cache yet — the next run builds one"
        return 0
    fi

    if [[ ! -w "$ASIMOV_CACHE_DIR" ]]; then
        doctor_problem "${ASIMOV_CACHE_DIR} is not writable by you"
        doctor_fix "rm -rf ${ASIMOV_CACHE_DIR}"
        return 0
    fi

    local file owner broken=0 root_owned=0
    for file in "$ASIMOV_EXCLUDED_STATE" "$ASIMOV_FAILED_STATE" \
                "$ASIMOV_MDFIND_SEEN" "$ASIMOV_PATH_CACHE"; do
        [[ -e "$file" ]] || continue
        if [[ ! -r "$file" || ! -w "$file" ]]; then
            broken=$((broken + 1))
            owner="$(stat -f '%Su' "$file" 2>/dev/null || echo 'unknown')"
            [[ "$owner" == "root" ]] && root_owned=$((root_owned + 1))
            doctor_problem "${file} is not readable and writable by you (owner: ${owner})"
        fi
    done

    if [[ "$broken" -gt 0 ]]; then
        # Only name root as the cause when root actually owns something: a
        # diagnosis that guesses wrong sends people chasing the wrong fix.
        if [[ "$root_owned" -gt 0 ]]; then
            doctor_fix "A run as root left these behind. Clear them:"
        else
            doctor_fix "Asimov can't use these. Clear them:"
        fi
        doctor_fix "rm -rf ${ASIMOV_CACHE_DIR}"
        return 0
    fi

    if [[ -r "$ASIMOV_PATH_CACHE" ]]; then
        local entries age
        entries="$(grep -cve '^#' -e '^$' "$ASIMOV_PATH_CACHE" 2>/dev/null || true)"
        doctor_ok "${entries:-0} cached paths"
        age="$(( $(date +%s) - $(stat -f '%m' "$ASIMOV_PATH_CACHE" 2>/dev/null || date +%s) ))"
        doctor_ok "last scan: $(doctor_humanise_age "$age")"
    else
        doctor_ok "cache is readable, no scan recorded yet"
    fi
    return 0
}

doctor_check_config() {
    doctor_heading 'Config'

    if [[ ! -f "$ASIMOV_CONFIG_FILE" ]]; then
        doctor_note "no config file — using defaults"
        return 0
    fi
    if [[ ! -r "$ASIMOV_CONFIG_FILE" ]]; then
        doctor_problem "${ASIMOV_CONFIG_FILE} is not readable by you"
        return 0
    fi

    # Same grammar load_config accepts, but here anything unrecognised is
    # reported instead of silently ignored — a typo'd key is invisible otherwise.
    local section="" line key unknown=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[([a-z_]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            case "$section" in
                fixed_dirs|scan|sentinels|skip_paths) ;;
                *)
                    unknown=$((unknown + 1))
                    doctor_problem "unknown section [${section}] in ${ASIMOV_CONFIG_FILE}"
                    ;;
            esac
            continue
        fi

        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            case "${section}:${key}" in
                fixed_dirs:enabled|fixed_dirs:extra|scan:extra|scan:dirs|\
                sentinels:extra|sentinels:disabled|skip_paths:extra) ;;
                *)
                    # A key under an already-reported section is the same fault.
                    case "$section" in
                        fixed_dirs|scan|sentinels|skip_paths)
                            unknown=$((unknown + 1))
                            doctor_problem "unknown key '${key}' under [${section}] in ${ASIMOV_CONFIG_FILE}"
                            ;;
                    esac
                    ;;
            esac
        fi
    done < "$ASIMOV_CONFIG_FILE"

    [[ "$unknown" -eq 0 ]] && doctor_ok "${ASIMOV_CONFIG_FILE} looks valid"
    return 0
}

# The data files are part of the install, so a missing or empty one is an install
# problem, not a user one. A run would abort on it; doctor should say so first.
doctor_check_data() {
    doctor_heading 'Data'

    local file name missing=0
    for name in sentinels fixed-dirs skip-paths; do
        file="${ASIMOV_DATA}/${name}.tsv"
        if [[ ! -r "$file" ]]; then
            missing=$((missing + 1))
            doctor_problem "missing data file: ${file}"
        fi
    done

    if [[ "$missing" -gt 0 ]]; then
        doctor_fix "This install is incomplete. Reinstall asimov."
        return 0
    fi

    # Safe to load now that every file is present: doctor is the one command that
    # must survive a broken install, so it checks before loading rather than after.
    load_data
    doctor_ok "${#ASIMOV_SENTINEL_DIR[@]} sentinels, ${#ASIMOV_FIXED_DIRS[@]} fixed directories (${ASIMOV_DATA})"
    return 0
}

doctor_check_time_machine() {
    doctor_heading 'Time Machine'

    if ! command -v tmutil >/dev/null 2>&1; then
        doctor_problem "tmutil not found — is this macOS?"
        return 0
    fi

    if tmutil isexcluded "$ASIMOV_ROOT" >/dev/null 2>&1; then
        doctor_ok "tmutil can read exclusions"
    else
        doctor_problem "tmutil cannot read exclusions — grant your terminal Full Disk Access"
        doctor_fix "System Settings → Privacy & Security → Full Disk Access"
    fi
    return 0
}

cmd_doctor() {
    [[ -n "$ASIMOV_QUIET" ]] || printf '\n%sAsimov doctor%s\n' \
        "$ASIMOV_COLOR_INFO" "$ASIMOV_COLOR_RESET"

    doctor_check_install
    doctor_check_schedule
    doctor_check_cache
    doctor_check_config
    doctor_check_data
    doctor_check_time_machine

    if [[ "$ASIMOV_DOCTOR_PROBLEMS" -eq 0 ]]; then
        [[ -n "$ASIMOV_QUIET" ]] || printf '\n%s✓%s No problems found.\n\n' \
            "$ASIMOV_COLOR_SUCCESS" "$ASIMOV_COLOR_RESET"
        return 0
    fi

    printf '\n%s problem%s found.\n\n' "$ASIMOV_DOCTOR_PROBLEMS" \
        "$([[ "$ASIMOV_DOCTOR_PROBLEMS" -eq 1 ]] || echo s)"
    return 1
}
