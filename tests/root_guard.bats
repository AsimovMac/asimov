#!/usr/bin/env bats
#
# Tests for the root/sudo guard and the styled error/warning messages.
#
# ASIMOV_TEST_UID simulates a root run; ASIMOV_TEST_INTERACTIVE simulates a
# terminal so the confirmation prompt is reachable from a non-tty test run.

load test_helper

# Run asimov as simulated root, feeding $1 to the confirmation prompt.
run_asimov_as_root() {
  local answer="$1"
  shift
  run env ASIMOV_TEST_UID=0 ASIMOV_TEST_INTERACTIVE=1 \
    bash -c "printf '%s\n' '${answer}' | '${BATS_TEST_DIRNAME}/../asimov' $*"
}

# =============================================================================
# Root / sudo guard
# =============================================================================

@test "warns when running as root" {
  create_project "Code/My-Project" "package.json" "node_modules"
  ASIMOV_TEST_UID=0 run_asimov
  [[ "$output" == *"running asimov as root (sudo)"* ]]
}

@test "root warning explains the better alternative" {
  ASIMOV_TEST_UID=0 run_asimov
  [[ "$output" == *"Do this instead:"* ]]
  [[ "$output" == *"launchctl kickstart"* ]]
  [[ "$output" == *"chown -R"* ]]
}

@test "continues without prompting when not interactive" {
  create_project "Code/My-Project" "package.json" "node_modules"
  ASIMOV_TEST_UID=0 run_asimov
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Non-interactive session"* ]]
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "aborts when the root confirmation is declined" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov_as_root "n"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"aborted"* ]]
  refute_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "aborts when the root confirmation is answered with a bare newline" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov_as_root ""
  [[ "$status" -eq 1 ]]
  refute_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "proceeds when the root confirmation is accepted" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov_as_root "y"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"continuing as root"* ]]
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "accepts a spelled-out yes at the root confirmation" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov_as_root "YES"
  [[ "$status" -eq 0 ]]
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "ASIMOV_ALLOW_ROOT skips the warning entirely" {
  create_project "Code/My-Project" "package.json" "node_modules"
  ASIMOV_TEST_UID=0 ASIMOV_ALLOW_ROOT=1 run_asimov
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"running asimov as root"* ]]
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "does not warn on a normal (non-root) run" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  [[ "$output" != *"running asimov as root"* ]]
}

@test "warns before doing any work in --dry-run too" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov_as_root "n" --dry-run
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"running asimov as root (sudo)"* ]]
}

# =============================================================================
# Styled diagnostics
# =============================================================================

@test "errors are prefixed with the error marker" {
  run_asimov --bogus-option
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"✗ asimov: unknown option '--bogus-option'"* ]]
}

@test "conflicting flags produce a styled error" {
  run_asimov --quiet --verbose
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"✗ asimov: --quiet and --verbose are mutually exclusive"* ]]
}

@test "a missing scan directory produces a styled error" {
  run_asimov "${HOME}/does-not-exist"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"✗ asimov: not a directory:"* ]]
}

@test "the root warning uses the warning marker" {
  ASIMOV_TEST_UID=0 run_asimov
  [[ "$output" == *"⚠ asimov: you are running asimov as root"* ]]
}

@test "diagnostics carry no ANSI codes when stderr is not a terminal" {
  run_asimov --bogus-option
  [[ "$output" != *$'\033['* ]]
}
