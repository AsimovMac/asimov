#!/usr/bin/env bats
#
# Tests for --spotlight: excluding discovered directories from Spotlight.
#
# Spotlight exclusion is a separate mechanism from Time Machine exclusion and
# must not gate on, or be gated by, it — a directory can be excluded from
# either, both, or neither.
#
# Actually applying the exclusion requires root (macOS only allows root to
# touch the Spotlight Privacy list), and Bats never runs as root, so the
# root-write path itself is untestable here — same precedent as ASIMOV_ROOT
# detection in behavior.bats. What's tested below is everything reachable
# unprivileged: the default-off behavior, the "requires root" warning, and
# the --dry-run preview.

load test_helper

@test "--spotlight is off by default (no Spotlight output)" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  [[ "$output" != *"Spotlight"* ]]
}

@test "--spotlight without root warns and changes nothing" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --spotlight
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"2 directories could be excluded from Spotlight"* ]]
  [[ "$output" == *"requires root"* || "$output" == *"root"* ]]
  [[ "$output" == *"sudo"* ]]
  [[ "$output" == *"--spotlight"* ]]
}

@test "--spotlight without root does not persist state (nothing was applied)" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --spotlight
  refute_spotlight_pending "${HOME}/Code/My-Project/node_modules"
}

@test "--spotlight without root repeats the warning on a second run" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --spotlight
  run_asimov --spotlight
  [[ "$output" == *"could be excluded from Spotlight"* ]]
}

@test "--quiet --spotlight suppresses the Spotlight warning" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --quiet --spotlight
  [[ "$output" != *"Spotlight"* ]]
}

@test "--dry-run --spotlight previews candidates without requiring root" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --dry-run --spotlight
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"2 directories would be excluded from Spotlight"* ]]
  [[ "$output" == *"${HOME}/Code/Project-A/node_modules"* ]]
  [[ "$output" == *"${HOME}/Code/Project-B/vendor"* ]]
}

@test "--dry-run --spotlight does not persist state" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run --spotlight
  refute_spotlight_pending "${HOME}/Code/My-Project/node_modules"
}

@test "--quiet --dry-run --spotlight suppresses the preview" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --quiet --dry-run --spotlight
  [[ "$output" != *"Spotlight"* ]]
}

# =============================================================================
# Independence from Time Machine exclusion — the core requirement: neither
# mechanism's already-excluded state gates the other.
# =============================================================================

@test "a path already excluded from Time Machine is still a Spotlight candidate" {
  create_project "Code/My-Project" "package.json" "node_modules"
  # First run: excludes from Time Machine, no --spotlight.
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"

  # Second run with --spotlight: the path is already TM-excluded (and thus
  # filtered out of Time Machine processing), but must still be reported as
  # a fresh Spotlight candidate since Spotlight state is untouched.
  run_asimov --spotlight
  [[ "$output" == *"could be excluded from Spotlight"* ]]
  [[ "$output" == *"${HOME}/Code/My-Project/node_modules"* || "$output" == *"1 director"* ]]
}

@test "a --spotlight run still excludes newly-discovered directories from Time Machine" {
  create_project "Code/My-Project" "package.json" "node_modules"
  # Time Machine exclusion always runs regardless of --spotlight — Spotlight
  # handling is additive, not a replacement.
  run_asimov --spotlight
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "--spotlight does not affect Time Machine exclusion count" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --spotlight
  [[ "$(count_exclusions)" -eq 2 ]]
}

# =============================================================================
# write_spotlight_exclusions — the root-only write path, unit-tested directly
# against a fixture plist (see load_write_spotlight_exclusions in
# test_helper.bash for why this doesn't need to run as root).
# =============================================================================

@test "write_spotlight_exclusions creates the Exclusions array when absent" {
  load_write_spotlight_exclusions
  local plist="${TEST_TEMP_DIR}/spotlight.plist"
  local candidates="${TEST_TEMP_DIR}/candidates"
  local state="${TEST_TEMP_DIR}/state"
  plutil -create xml1 "$plist"
  printf '%s\n' "/path/one" > "$candidates"
  touch "$state"

  run write_spotlight_exclusions "$candidates" "$plist" "$state"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"EXCLUDED 1"* ]]
  [[ "$output" == *"FAILED 0"* ]]
  [[ "$(plutil -p "$plist")" == *"/path/one"* ]]
}

@test "write_spotlight_exclusions adds every candidate as its own plutil call (not one batched invocation)" {
  # Regression test: plutil on this platform rejects multiple -insert clauses
  # in a single invocation, so a naive batched command silently does nothing.
  load_write_spotlight_exclusions
  local plist="${TEST_TEMP_DIR}/spotlight.plist"
  local candidates="${TEST_TEMP_DIR}/candidates"
  local state="${TEST_TEMP_DIR}/state"
  plutil -create xml1 "$plist"
  printf '%s\n' "/path/one" "/path/two" "/path/three" > "$candidates"
  touch "$state"

  run write_spotlight_exclusions "$candidates" "$plist" "$state"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"EXCLUDED 3"* ]]
  local extracted
  extracted="$(plutil -p "$plist")"
  [[ "$extracted" == *"/path/one"* ]]
  [[ "$extracted" == *"/path/two"* ]]
  [[ "$extracted" == *"/path/three"* ]]
}

@test "write_spotlight_exclusions records every applied path in the state file" {
  load_write_spotlight_exclusions
  local plist="${TEST_TEMP_DIR}/spotlight.plist"
  local candidates="${TEST_TEMP_DIR}/candidates"
  local state="${TEST_TEMP_DIR}/state"
  plutil -create xml1 "$plist"
  printf '%s\n' "/path/one" "/path/two" > "$candidates"
  touch "$state"

  write_spotlight_exclusions "$candidates" "$plist" "$state"
  grep -Fxq "/path/one" "$state"
  grep -Fxq "/path/two" "$state"
}

@test "write_spotlight_exclusions appends to an already-existing Exclusions array without clobbering it" {
  load_write_spotlight_exclusions
  local plist="${TEST_TEMP_DIR}/spotlight.plist"
  local candidates="${TEST_TEMP_DIR}/candidates"
  local state="${TEST_TEMP_DIR}/state"
  plutil -create xml1 "$plist"
  plutil -insert Exclusions -array "$plist"
  plutil -insert Exclusions.0 -string "/already/there" "$plist"
  printf '%s\n' "/path/new" > "$candidates"
  touch "$state"

  write_spotlight_exclusions "$candidates" "$plist" "$state"
  local extracted
  extracted="$(plutil -p "$plist")"
  [[ "$extracted" == *"/already/there"* ]]
  [[ "$extracted" == *"/path/new"* ]]
}

@test "write_spotlight_exclusions reports a failed path without stopping the rest" {
  load_write_spotlight_exclusions
  local plist="${TEST_TEMP_DIR}/spotlight.plist"
  local candidates="${TEST_TEMP_DIR}/candidates"
  local state="${TEST_TEMP_DIR}/state"
  plutil -create xml1 "$plist"
  # Make the plist read-only so every plutil -insert call fails, simulating a
  # write failure without needing to fake a real permissions-denied scenario.
  chmod 444 "$plist"
  printf '%s\n' "/path/one" > "$candidates"
  touch "$state"

  run write_spotlight_exclusions "$candidates" "$plist" "$state"
  [[ "$output" == *"EXCLUDED 0"* ]]
  [[ "$output" == *"FAILED 1"* ]]
  [[ ! -s "$state" ]]
  chmod 644 "$plist"
}
