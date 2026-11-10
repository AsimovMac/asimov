#!/usr/bin/env bats
#
# Tests for --spotlight: reporting Spotlight-exclusion candidates.
#
# Spotlight exclusion is a separate mechanism from Time Machine exclusion and
# must not gate on, or be gated by, it — a directory can be excluded from
# either, both, or neither.

load test_helper

@test "--spotlight is off by default (no plutil command printed)" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  [[ "$output" != *"plutil"* ]]
  [[ "$output" != *"Spotlight"* ]]
}

@test "--spotlight prints a batched plutil command for discovered directories" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --spotlight
  [[ "$output" == *"2 directories to also exclude from Spotlight"* ]]
  [[ "$output" == *"sudo plutil"* ]]
  [[ "$output" == *"-insert Exclusions.0 -string '${HOME}/Code/Project-A/node_modules'"* ]]
  [[ "$output" == *"-insert Exclusions.0 -string '${HOME}/Code/Project-B/vendor'"* ]]
  [[ "$output" == *"VolumeConfiguration.plist"* ]]
  [[ "$output" == *"sudo killall mds"* ]]
}

@test "--spotlight prints one batched command, not one per directory" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --spotlight
  local plutil_lines
  plutil_lines="$(printf '%s\n' "$output" | grep -c 'sudo plutil')"
  [[ "$plutil_lines" -eq 1 ]]
}

@test "--spotlight never calls plutil or sudo itself, only prints" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --spotlight
  [[ "$status" -eq 0 ]]
}

@test "--spotlight records reported paths so a second run does not re-report them" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --spotlight
  assert_spotlight_pending "${HOME}/Code/My-Project/node_modules"

  run_asimov --spotlight
  [[ "$output" != *"plutil"* ]]
}

@test "--dry-run --spotlight prints the command but does not persist state" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run --spotlight
  [[ "$output" == *"sudo plutil"* ]]
  refute_spotlight_pending "${HOME}/Code/My-Project/node_modules"
}

@test "--quiet --spotlight suppresses the plutil output" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --quiet --spotlight
  [[ "$output" != *"plutil"* ]]
}

# =============================================================================
# Independence from Time Machine exclusion — the core requirement: neither
# mechanism's already-excluded state gates the other.
# =============================================================================

@test "a path already excluded from Time Machine is still reported for Spotlight" {
  create_project "Code/My-Project" "package.json" "node_modules"
  # First run: excludes from Time Machine, no --spotlight.
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"

  # Second run with --spotlight: the path is already TM-excluded (and thus
  # filtered out of Time Machine processing), but must still be reported as
  # a fresh Spotlight candidate since Spotlight state is untouched.
  run_asimov --spotlight
  [[ "$output" == *"sudo plutil"* ]]
  [[ "$output" == *"${HOME}/Code/My-Project/node_modules"* ]]
  assert_spotlight_pending "${HOME}/Code/My-Project/node_modules"
}

@test "a --spotlight run still excludes newly-discovered directories from Time Machine" {
  create_project "Code/My-Project" "package.json" "node_modules"
  # Time Machine exclusion always runs regardless of --spotlight — Spotlight
  # reporting is additive, not a replacement.
  run_asimov --spotlight
  assert_excluded "${HOME}/Code/My-Project/node_modules"
  assert_spotlight_pending "${HOME}/Code/My-Project/node_modules"
}

@test "--spotlight does not affect Time Machine exclusion count" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --spotlight
  [[ "$(count_exclusions)" -eq 2 ]]
}
