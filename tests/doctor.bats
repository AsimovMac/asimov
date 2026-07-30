#!/usr/bin/env bats
#
# Tests for `asimov doctor` — the diagnostic subcommand.
#
# Doctor exists mainly for people arriving from v0.3.0 (issue #122), where the
# failure modes are leftovers: a shadowed binary, an orphaned LaunchAgent, and a
# root-owned cache. It is read-only: it reports and prints commands, never runs
# them, and never executes another asimov binary it finds.

load test_helper

# The shared setup() from test_helper applies. With ASIMOV_TEST_LAUNCHCTL_LOADED
# unset, the mock launchctl reports nothing as loaded — the right baseline.

require_non_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    skip "chmod-based tests are meaningless as root"
  fi
}

# =============================================================================
# Plumbing
# =============================================================================

@test "doctor runs and exits 0 on a clean system" {
  run_asimov doctor
  [[ "$status" -eq 0 ]]
}

@test "doctor is listed in the help output" {
  run_asimov --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"asimov doctor"* ]]
}

@test "doctor reports the running version" {
  # Derived from the script, never hardcoded: a literal here breaks on every
  # release, which is exactly what it did on the bump to 0.11.0.
  run_asimov --version
  local version="$output"
  [[ -n "$version" ]]

  run_asimov doctor
  [[ "$output" == *"$version"* ]]
}

@test "doctor never modifies Time Machine exclusions" {
  create_project "Code/My-Project" "package.json" "node_modules"

  run_asimov doctor

  [[ "$(count_exclusions)" -eq 0 ]]
  refute_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "doctor does not create a cache" {
  run_asimov doctor
  [[ ! -e "${HOME}/.cache/asimov/paths" ]]
}

@test "doctor --quiet prints nothing when everything is healthy" {
  run_asimov doctor --quiet
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

# =============================================================================
# Install / shadowed binaries
# =============================================================================

@test "doctor flags an older asimov shadowing the one that is running" {
  shadow_asimov_binary "0.3.0" >/dev/null

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"shadow"* ]]
  [[ "$output" == *"0.3.0"* ]]
}

@test "doctor reads the shadowing binary's version without executing it" {
  shadow_asimov_binary "0.3.0" >/dev/null

  run_asimov doctor

  # The stub screams if it is ever run. v0.3.0 parses no arguments at all, so
  # executing it to ask its version would start a real scan instead.
  [[ "$output" != *"STUB WAS EXECUTED"* ]]
}

@test "doctor is clean when no other asimov is on PATH" {
  run_asimov doctor
  [[ "$output" != *"shadow"* ]]
}

# =============================================================================
# Schedule
# =============================================================================

@test "doctor reports a loaded schedule as healthy" {
  write_launch_agent "com.stevegrunwell.asimov" "$(command -v bash)"
  set_loaded_agents "com.stevegrunwell.asimov"

  run_asimov doctor

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"com.stevegrunwell.asimov"* ]]
  [[ "$output" == *"loaded"* ]]
}

@test "doctor flags a plist whose program no longer exists" {
  write_launch_agent "homebrew.mxcl.asimov" "/opt/homebrew/Cellar/asimov/0.3.0/bin/asimov"
  set_loaded_agents "homebrew.mxcl.asimov"

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"homebrew.mxcl.asimov"* ]]
  [[ "$output" == *"/opt/homebrew/Cellar/asimov/0.3.0/bin/asimov"* ]]
  [[ "$output" == *"no longer exists"* ]]
}

@test "doctor flags two schedules running at once" {
  write_launch_agent "com.stevegrunwell.asimov" "$(command -v bash)"
  write_launch_agent "com.django23.asimov" "$(command -v bash)"
  set_loaded_agents "com.stevegrunwell.asimov com.django23.asimov"

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"two schedules"* || "$output" == *"more than one"* ]]
}

@test "doctor prints the bootout command for an orphaned agent" {
  write_launch_agent "homebrew.mxcl.asimov" "/gone/asimov"
  set_loaded_agents "homebrew.mxcl.asimov"

  run_asimov doctor

  [[ "$output" == *"launchctl bootout"* ]]
  [[ "$output" == *"homebrew.mxcl.asimov"* ]]
}

@test "doctor says so when nothing is scheduled" {
  run_asimov doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"not scheduled"* ]]
}

@test "doctor treats an unloaded legacy agent as a leftover to remove" {
  write_launch_agent "com.django23.asimov" "$(command -v bash)"
  set_loaded_agents

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"leftover"* ]]
  [[ "$output" == *"rm ${HOME}/Library/LaunchAgents/com.django23.asimov.plist"* ]]
  # Never advise loading a label we no longer ship.
  [[ "$output" != *"bootstrap"* ]]
}

@test "doctor offers to load an unloaded current agent" {
  write_launch_agent "com.stevegrunwell.asimov" "$(command -v bash)"
  set_loaded_agents

  run_asimov doctor

  [[ "$output" == *"bootstrap"* ]]
}

@test "doctor flags a plist that is installed but not loaded" {
  write_launch_agent "com.stevegrunwell.asimov" "$(command -v bash)"
  set_loaded_agents

  run_asimov doctor

  [[ "$output" == *"not loaded"* ]]
}

# =============================================================================
# Cache
# =============================================================================

@test "doctor flags an unreadable cache file and prints the reset command" {
  require_non_root
  mkdir -p "${HOME}/.cache/asimov"
  echo "/x" > "${HOME}/.cache/asimov/excluded"
  chmod 000 "${HOME}/.cache/asimov/excluded"

  run_asimov doctor
  chmod 644 "${HOME}/.cache/asimov/excluded"

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"excluded"* ]]
  [[ "$output" == *"rm -rf ${HOME}/.cache/asimov"* ]]
}

@test "doctor does not blame root for a cache file you own" {
  require_non_root
  mkdir -p "${HOME}/.cache/asimov"
  echo "/x" > "${HOME}/.cache/asimov/excluded"
  chmod 000 "${HOME}/.cache/asimov/excluded"

  run_asimov doctor
  chmod 644 "${HOME}/.cache/asimov/excluded"

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"rm -rf ${HOME}/.cache/asimov"* ]]
  # The file is owned by the current user; root never touched it.
  [[ "$output" != *"as root"* ]]
}

@test "doctor flags an unwritable cache directory" {
  require_non_root
  mkdir -p "${HOME}/.cache/asimov"
  chmod 500 "${HOME}/.cache/asimov"

  run_asimov doctor
  chmod 700 "${HOME}/.cache/asimov"

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"not writable"* ]]
}

@test "doctor reports a healthy cache with its entry count" {
  write_path_cache "${HOME}/a" "${HOME}/b"

  run_asimov doctor

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"2"* ]]
}

@test "doctor says when the last scan ran" {
  write_path_cache "${HOME}/a"

  run_asimov doctor

  [[ "$output" == *"last scan"* ]]
}

@test "doctor reports no cache yet as healthy, not a problem" {
  run_asimov doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"no cache yet"* ]]
}

# =============================================================================
# Config
# =============================================================================

@test "doctor reports a valid config file" {
  write_config "[fixed_dirs]
enabled = true"

  run_asimov doctor

  [[ "$status" -eq 0 ]]
  [[ "$output" == *".config/asimov/config"* ]]
}

@test "doctor flags an unknown config key" {
  write_config "[fixed_dirs]
enbaled = true"

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"enbaled"* ]]
}

@test "doctor flags an unknown config section" {
  write_config "[fixed_dris]
enabled = true"

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"fixed_dris"* ]]
}

@test "doctor reports the default when there is no config file" {
  run_asimov doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"defaults"* ]]
}

# =============================================================================
# Time Machine
# =============================================================================

@test "doctor reports tmutil as reachable" {
  run_asimov doctor
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Time Machine"* ]]
}

@test "doctor flags tmutil being unable to read exclusions" {
  ASIMOV_TEST_TMUTIL_ISEXCLUDED_FAIL=1
  export ASIMOV_TEST_TMUTIL_ISEXCLUDED_FAIL

  run_asimov doctor

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Full Disk Access"* ]]
}

# =============================================================================
# Summary
# =============================================================================

@test "doctor summarises the problem count" {
  write_launch_agent "homebrew.mxcl.asimov" "/gone/asimov"
  set_loaded_agents "homebrew.mxcl.asimov"

  run_asimov doctor

  [[ "$output" == *"1 problem"* ]]
}

@test "doctor says everything checks out when healthy" {
  run_asimov doctor
  [[ "$output" == *"No problems found"* ]]
}
