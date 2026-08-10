#!/usr/bin/env bash
# shellcheck shell=bash
#
# The optional config file at ~/.config/asimov/config.
#
# Grammar: [section] headers, key = value lines, # comments, blank lines.
# Unrecognised sections and keys are ignored here and reported by `asimov doctor`,
# so a typo is visible without breaking a run.

# Populate ASIMOV_CONFIG_* from the config file. A missing file is not an error.
load_config() {
    ASIMOV_CONFIG_FIXED_DIRS_ENABLED=false
    ASIMOV_CONFIG_EXTRA_FIXED_DIRS=()
    ASIMOV_CONFIG_EXTRA_SENTINELS=()
    ASIMOV_CONFIG_DISABLED_SENTINELS=()
    ASIMOV_CONFIG_SCAN_DIRS=()
    ASIMOV_CONFIG_SCAN_DIRS_ONLY=()
    ASIMOV_CONFIG_EXTRA_SKIP_PATHS=()

    [[ -f "$ASIMOV_CONFIG_FILE" ]] || return 0

    local section="" line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[([a-z_]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$line" =~ ^([a-z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value%"${value##*[![:space:]]}"}"

            case "${section}:${key}" in
                fixed_dirs:enabled)
                    ASIMOV_CONFIG_FIXED_DIRS_ENABLED="$value"
                    ;;
                fixed_dirs:extra)
                    value="${value/#\~/$HOME}"
                    ASIMOV_CONFIG_EXTRA_FIXED_DIRS+=("$value")
                    ;;
                scan:extra)
                    value="${value/#\~/$HOME}"
                    ASIMOV_CONFIG_SCAN_DIRS+=("$value")
                    ;;
                scan:dirs)
                    value="${value/#\~/$HOME}"
                    ASIMOV_CONFIG_SCAN_DIRS_ONLY+=("$value")
                    ;;
                sentinels:extra)
                    ASIMOV_CONFIG_EXTRA_SENTINELS+=("$value")
                    ;;
                sentinels:disabled)
                    ASIMOV_CONFIG_DISABLED_SENTINELS+=("$value")
                    ;;
                skip_paths:extra)
                    value="${value/#\~/$HOME}"
                    ASIMOV_CONFIG_EXTRA_SKIP_PATHS+=("$value")
                    ;;
            esac
        fi
    done < "$ASIMOV_CONFIG_FILE"
}
