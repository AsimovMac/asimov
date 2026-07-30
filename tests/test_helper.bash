#!/usr/bin/env bash
#
# Bats test helper for the Asimov test suite.

# Set up a clean, isolated environment for each test.
setup() {
  TEST_TEMP_DIR="$(mktemp -d)"
  export HOME="$TEST_TEMP_DIR"
  export PATH="${BATS_TEST_DIRNAME}/bin:$PATH"

  # Drop any real asimov install from PATH. `asimov doctor` inspects PATH, so
  # without this the suite would report a different result on every machine
  # depending on whether the developer has asimov installed, and which version.
  local clean_path="" path_dir
  while IFS= read -r path_dir; do
    [[ -n "$path_dir" ]] || continue
    [[ -x "${path_dir}/asimov" ]] && continue
    clean_path="${clean_path:+${clean_path}:}${path_dir}"
  done < <(printf '%s\n' "${PATH//:/$'\n'}")
  export PATH="$clean_path"

  ASIMOV_TEST_EXCLUSIONS="${TEST_TEMP_DIR}/.exclusions"
  export ASIMOV_TEST_EXCLUSIONS
  touch "$ASIMOV_TEST_EXCLUSIONS"

  # How to launch the script under test. asimov's shebang is #!/usr/bin/env bash,
  # so in real use it runs under whichever bash comes first on PATH: 3.2 on a
  # stock Mac, 5.x on most development machines. ASIMOV_TEST_BASH pins that
  # interpreter so CI can run the whole suite under each, and Bats keeps running
  # under its own bash either way.
  if [[ -n "${ASIMOV_TEST_BASH:-}" ]]; then
    ASIMOV_CMD=("$ASIMOV_TEST_BASH" "${BATS_TEST_DIRNAME}/../asimov")
  else
    ASIMOV_CMD=("${BATS_TEST_DIRNAME}/../asimov")
  fi
}

# Clean up the temporary directory after each test.
teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# Create a project directory with a sentinel file and dependency directory.
#
# Usage: create_project <base_dir> <sentinel_file> <deps_dir>
#
# Example: create_project "Code/My-Project" "package.json" "node_modules"
create_project() {
  local base="$1"
  local sentinel="$2"
  local deps_dir="$3"

  mkdir -p "${HOME}/${base}/${deps_dir}"
  echo "sentinel" > "${HOME}/${base}/${sentinel}"
}

# Run the asimov script under test. Pass any arguments (e.g. --dry-run, --help).
run_asimov() {
  run "${ASIMOV_CMD[@]}" "$@"
}

# Return the number of exclusions recorded by the mock tmutil.
count_exclusions() {
  local count
  count="$(wc -l < "$ASIMOV_TEST_EXCLUSIONS" | tr -d ' ')"
  echo "$count"
}

# Assert that a path was excluded by the mock tmutil.
assert_excluded() {
  local path="$1"
  if ! grep -Fxq "$path" "$ASIMOV_TEST_EXCLUSIONS"; then
    echo "Expected '$path' to be excluded, but it was not." >&2
    echo "Exclusions:" >&2
    cat "$ASIMOV_TEST_EXCLUSIONS" >&2
    return 1
  fi
}

# Assert that a path was NOT excluded by the mock tmutil.
refute_excluded() {
  local path="$1"
  if grep -Fxq "$path" "$ASIMOV_TEST_EXCLUSIONS"; then
    echo "Expected '$path' to NOT be excluded, but it was." >&2
    echo "Exclusions:" >&2
    cat "$ASIMOV_TEST_EXCLUSIONS" >&2
    return 1
  fi
}

# Write a config file for testing.
#
# Usage: write_config "config file contents"
#
# Example: write_config "[fixed_dirs]
# enabled = true"
write_config() {
    local config_dir="${HOME}/.config/asimov"
    mkdir -p "$config_dir"
    printf '%s\n' "$1" > "${config_dir}/config"
}

# Write a path cache file for testing.
#
# Usage: write_path_cache "path1" "path2" ...
write_path_cache() {
    local cache_dir="${HOME}/.cache/asimov"
    mkdir -p "$cache_dir"
    {
        echo "# asimov path cache — updated 2026-01-01T00:00:00Z"
        for path in "$@"; do
            echo "$path"
        done
    } > "${cache_dir}/paths"
}

# Read the path cache file, stripping comments and blank lines.
read_path_cache() {
    local cache_file="${HOME}/.cache/asimov/paths"
    [[ -f "$cache_file" ]] || return 0
    grep -v '^#' "$cache_file" | grep -v '^$' || true
}

# Assert that a path is present in the path cache.
assert_cached() {
    local path="$1"
    local cache_file="${HOME}/.cache/asimov/paths"
    if [[ ! -f "$cache_file" ]]; then
        echo "Expected cache file to exist, but it does not." >&2
        return 1
    fi
    if ! grep -Fxq "$path" "$cache_file"; then
        echo "Expected '$path' to be in cache, but it was not." >&2
        echo "Cache contents:" >&2
        cat "$cache_file" >&2
        return 1
    fi
}

# Assert that a path is NOT present in the path cache.
refute_cached() {
    local path="$1"
    local cache_file="${HOME}/.cache/asimov/paths"
    if [[ ! -f "$cache_file" ]]; then
        return 0
    fi
    if grep -Fxq "$path" "$cache_file"; then
        echo "Expected '$path' to NOT be in cache, but it was." >&2
        echo "Cache contents:" >&2
        cat "$cache_file" >&2
        return 1
    fi
}

# Write a failed-path state file for testing.
#
# Usage: write_failed_state "path1" "path2" ...
write_failed_state() {
    local cache_dir="${HOME}/.cache/asimov"
    mkdir -p "$cache_dir"
    printf '%s\n' "$@" > "${cache_dir}/failed"
}

# Assert that a path is present in the failed-path state.
assert_failed() {
    local path="$1"
    local failed_file="${HOME}/.cache/asimov/failed"
    if [[ ! -f "$failed_file" ]]; then
        echo "Expected failed state file to exist, but it does not." >&2
        return 1
    fi
    if ! grep -Fxq "$path" "$failed_file"; then
        echo "Expected '$path' to be in failed state, but it was not." >&2
        echo "Failed state contents:" >&2
        cat "$failed_file" >&2
        return 1
    fi
}

# Assert that a path is NOT present in the failed-path state.
refute_failed() {
    local path="$1"
    local failed_file="${HOME}/.cache/asimov/failed"
    [[ -f "$failed_file" ]] || return 0
    if grep -Fxq "$path" "$failed_file"; then
        echo "Expected '$path' to NOT be in failed state, but it was." >&2
        echo "Failed state contents:" >&2
        cat "$failed_file" >&2
        return 1
    fi
}

# Load format_size_kb and its constants for unit testing.
# Extracts just the constants and function from the main script
# without executing the rest of the script.
load_format_size_kb() {
    eval "$(awk '/^readonly ASIMOV_KB_PER/; /^format_size_kb\(\)/,/^}/' "${BATS_TEST_DIRNAME}/../asimov")"
}

# Write a Time Machine preferences fixture holding a sticky exclusion list
# (the SkipPaths array written by `tmutil addexclusion -p`), and point the
# script at it via ASIMOV_TM_PLIST.
#
# Usage: write_sticky_exclusions "/path/one" "/path/two"
write_sticky_exclusions() {
    local plist="${TEST_TEMP_DIR}/com.apple.TimeMachine.plist"
    local path
    /usr/libexec/PlistBuddy -c "Add :SkipPaths array" "$plist" >/dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c "Delete :SkipPaths" -c "Add :SkipPaths array" "$plist" >/dev/null 2>&1
    for path in "$@"; do
        /usr/libexec/PlistBuddy -c "Add :SkipPaths: string ${path}" "$plist" >/dev/null
    done
    export ASIMOV_TM_PLIST="$plist"
}

# Write a LaunchAgent plist into the (temp) home, as an install would.
#
# Usage: write_launch_agent <label> [program_path]
#
# Example: write_launch_agent "homebrew.mxcl.asimov" "/opt/homebrew/bin/asimov"
write_launch_agent() {
    local label="$1"
    local program="${2:-/usr/local/bin/asimov}"
    local dir="${HOME}/Library/LaunchAgents"
    mkdir -p "$dir"
    cat > "${dir}/${label}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>Program</key>
    <string>${program}</string>
    <key>StartInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST
}

# Mark a LaunchAgent label as loaded for the mock launchctl.
#
# Usage: set_loaded_agents "com.stevegrunwell.asimov" "homebrew.mxcl.asimov"
set_loaded_agents() {
    ASIMOV_TEST_LAUNCHCTL_LOADED="$*"
    export ASIMOV_TEST_LAUNCHCTL_LOADED
}

# Put a fake `asimov` executable earlier on PATH than the script under test,
# to simulate a leftover install from an older version shadowing the new one.
# The stub must never be executed by doctor — it exits 1 loudly if it is.
#
# Usage: shadow_asimov_binary <version>   (echoes the directory it created)
shadow_asimov_binary() {
    local version="$1"
    local dir="${TEST_TEMP_DIR}/shadow-bin"
    mkdir -p "$dir"
    cat > "${dir}/asimov" <<STUB
#!/usr/bin/env bash
# @version ${version}
echo "STUB WAS EXECUTED" >&2
exit 1
STUB
    chmod +x "${dir}/asimov"
    export PATH="${dir}:$PATH"
    echo "$dir"
}
