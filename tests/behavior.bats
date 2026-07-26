#!/usr/bin/env bats
#
# Behavioral tests: negative cases, multi-match, idempotency, skip paths, nesting.

load test_helper

# =============================================================================
# Negative tests: directory without sentinel should NOT be excluded
# =============================================================================

@test "does not exclude node_modules without package.json" {
  mkdir -p "${HOME}/Code/My-Project/node_modules"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/node_modules"
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not exclude vendor without any sentinel" {
  mkdir -p "${HOME}/Code/My-Project/vendor"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/vendor"
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not exclude target without any sentinel" {
  mkdir -p "${HOME}/Code/My-Project/target"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/target"
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not exclude .venv without any sentinel" {
  mkdir -p "${HOME}/Code/My-Project/.venv"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/.venv"
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not exclude DerivedData without *.xcodeproj" {
  mkdir -p "${HOME}/Code/My-Project/DerivedData"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/DerivedData"
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not exclude bin without any .NET project file" {
  mkdir -p "${HOME}/Code/My-Project/bin"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/bin"
  [[ "$(count_exclusions)" -eq 0 ]]
}

# =============================================================================
# Multi-match and deduplication
# =============================================================================

@test "finds multiple matches in a single run" {
  create_project "Code/First-Project" "composer.json" "vendor"
  create_project "Code/Second-Project" "composer.json" "vendor"
  run_asimov
  assert_excluded "${HOME}/Code/First-Project/vendor"
  assert_excluded "${HOME}/Code/Second-Project/vendor"
  [[ "$(count_exclusions)" -eq 2 ]]
}

@test "finds multiple different dependency types in a single run" {
  create_project "Code/Node-Project" "package.json" "node_modules"
  create_project "Code/Rust-Project" "Cargo.toml" "target"
  create_project "Code/Python-Project" "requirements.txt" ".venv"
  run_asimov
  assert_excluded "${HOME}/Code/Node-Project/node_modules"
  assert_excluded "${HOME}/Code/Rust-Project/target"
  assert_excluded "${HOME}/Code/Python-Project/.venv"
  [[ "$(count_exclusions)" -eq 3 ]]
}

@test "excludes same directory when multiple sentinels match" {
  # A project with both build.gradle and build.gradle.kts should still
  # only exclude .gradle once (deduplication by find -prune).
  create_project "Code/My-Project" "build.gradle" ".gradle"
  echo "sentinel" > "${HOME}/Code/My-Project/build.gradle.kts"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/.gradle"
}

# =============================================================================
# Idempotency
# =============================================================================

@test "does not re-exclude already excluded paths" {
  create_project "Code/My-Project" "composer.json" "vendor"
  run_asimov

  local first_count
  first_count="$(count_exclusions)"
  [[ "$first_count" -eq 1 ]]

  run_asimov

  local second_count
  second_count="$(count_exclusions)"
  [[ "$second_count" -eq 1 ]]
}

# =============================================================================
# Skip paths
# =============================================================================

@test "does not check paths inside .Trash" {
  mkdir -p "${HOME}/.Trash/My-Project/vendor"
  echo "sentinel" > "${HOME}/.Trash/My-Project/composer.json"
  run_asimov
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not check paths inside ~/Library" {
  mkdir -p "${HOME}/Library/My-Project/node_modules"
  echo "sentinel" > "${HOME}/Library/My-Project/package.json"
  run_asimov
  [[ "$(count_exclusions)" -eq 0 ]]
}

# =============================================================================
# Nested project handling
# =============================================================================

@test "excludes dependency directory in nested project structure" {
  create_project "Code/Parent/Child" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/Parent/Child/node_modules"
  [[ "$(count_exclusions)" -eq 1 ]]
}

@test "excludes directory when project path contains spaces" {
  create_project "Code/My Project" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/My Project/node_modules"
  [[ "$(count_exclusions)" -eq 1 ]]
}

# =============================================================================
# ASIMOV_ROOT detection
# =============================================================================
# When not root, ASIMOV_ROOT equals HOME (verified below). When running as root
# (e.g. launchd/sudo), ASIMOV_ROOT is the console user's home — that path is
# tested manually or via integration; full simulation would require mocked stat/dscl.

@test "uses HOME as root directory when not running as root" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"
  [[ "$(count_exclusions)" -eq 1 ]]
}

@test "exits with error when root directory does not exist" {
  run env HOME=/nonexistent-asimov-root "${ASIMOV_CMD[@]}"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"root directory"* ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "does not descend into excluded dependency directories" {
  # A node_modules inside another node_modules should not be separately excluded
  create_project "Code/My-Project" "package.json" "node_modules"
  mkdir -p "${HOME}/Code/My-Project/node_modules/dep/node_modules"
  echo "sentinel" > "${HOME}/Code/My-Project/node_modules/dep/package.json"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"
  refute_excluded "${HOME}/Code/My-Project/node_modules/dep/node_modules"
  [[ "$(count_exclusions)" -eq 1 ]]
}

# =============================================================================
# Skip already-excluded directories (mdfind optimization)
# =============================================================================

@test "skips directories already excluded from Time Machine" {
  create_project "Code/Already-Excluded" "package.json" "node_modules"
  create_project "Code/New-Project" "package.json" "node_modules"

  # Pre-exclude the first project manually
  echo "${HOME}/Code/Already-Excluded/node_modules" > "$ASIMOV_TEST_EXCLUSIONS"

  # Tell mock mdfind to report the exact path as already excluded
  ASIMOV_TEST_MDFIND_RESULTS="${TEST_TEMP_DIR}/.mdfind_results"
  export ASIMOV_TEST_MDFIND_RESULTS
  echo "${HOME}/Code/Already-Excluded/node_modules" > "$ASIMOV_TEST_MDFIND_RESULTS"

  run_asimov

  # The new project should be excluded
  assert_excluded "${HOME}/Code/New-Project/node_modules"
  # Total exclusions: 1 pre-existing + 1 newly added = 2
  [[ "$(count_exclusions)" -eq 2 ]]
}

# =============================================================================
# Fixed directories (global caches)
# =============================================================================

@test "does not exclude fixed directories by default (no config)" {
  mkdir -p "${HOME}/.cache"
  run_asimov
  refute_excluded "${HOME}/.cache"
}

@test "excludes fixed directory when config enables them" {
  mkdir -p "${HOME}/.cache"
  write_config "[fixed_dirs]
enabled = true"
  run_asimov
  assert_excluded "${HOME}/.cache"
}

@test "does not fail when fixed directory does not exist" {
  write_config "[fixed_dirs]
enabled = true"
  run_asimov --no-cache
  [[ "$status" -eq 0 ]]
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "excludes multiple fixed directories when config enables them" {
  mkdir -p "${HOME}/.cache"
  mkdir -p "${HOME}/.gradle/caches"
  mkdir -p "${HOME}/.npm/_cacache"
  write_config "[fixed_dirs]
enabled = true"
  run_asimov
  assert_excluded "${HOME}/.cache"
  assert_excluded "${HOME}/.gradle/caches"
  assert_excluded "${HOME}/.npm/_cacache"
  [[ "$(count_exclusions)" -eq 3 ]]
}

@test "excludes the Go module cache when fixed dirs are enabled" {
  mkdir -p "${HOME}/go/pkg/mod"
  write_config "[fixed_dirs]
enabled = true"
  run_asimov
  assert_excluded "${HOME}/go/pkg/mod"
}

@test "excludes the Go module cache as a whole, not each vendor dir inside it" {
  # Real-world shape: the module cache holds many read-only vendor/ dirs behind
  # @-versioned paths. Excluding the cache root covers all of them in one call;
  # excluding each individually would be ~11s apiece and fail on the 0555 perms.
  create_project "go/pkg/mod/github.com/foo/bar@v1.2.3" "go.mod" "vendor"
  write_config "[fixed_dirs]
enabled = true"

  run_asimov

  assert_excluded "${HOME}/go/pkg/mod"
  refute_excluded "${HOME}/go/pkg/mod/github.com/foo/bar@v1.2.3/vendor"
}

@test "does not re-exclude already excluded fixed directory" {
  mkdir -p "${HOME}/.cache"
  write_config "[fixed_dirs]
enabled = true"
  run_asimov
  assert_excluded "${HOME}/.cache"
  local first_count
  first_count="$(count_exclusions)"
  [[ "$first_count" -eq 1 ]]

  run_asimov
  local second_count
  second_count="$(count_exclusions)"
  [[ "$second_count" -eq 1 ]]
}

# =============================================================================
# Config file
# =============================================================================

@test "config: missing config file is silently ignored" {
  run_asimov
  [[ "$status" -eq 0 ]]
}

@test "config: unknown section is silently ignored" {
  write_config "[unknown_section]
foo = bar"
  run_asimov
  [[ "$status" -eq 0 ]]
}

@test "config: unknown key is silently ignored" {
  write_config "[fixed_dirs]
unknown_key = value"
  run_asimov
  [[ "$status" -eq 0 ]]
}

@test "config: extra fixed dir is excluded" {
  mkdir -p "${HOME}/.custom-cache"
  write_config "[fixed_dirs]
extra = ~/.custom-cache"
  run_asimov
  assert_excluded "${HOME}/.custom-cache"
}

@test "config: extra fixed dir is excluded even when fixed_dirs disabled" {
  mkdir -p "${HOME}/.custom-cache"
  write_config "[fixed_dirs]
enabled = false
extra = ~/.custom-cache"
  run_asimov
  assert_excluded "${HOME}/.custom-cache"
}

@test "config: multiple extra fixed dirs" {
  mkdir -p "${HOME}/.cache-a"
  mkdir -p "${HOME}/.cache-b"
  write_config "[fixed_dirs]
extra = ~/.cache-a
extra = ~/.cache-b"
  run_asimov
  assert_excluded "${HOME}/.cache-a"
  assert_excluded "${HOME}/.cache-b"
}

@test "config: extra sentinel pair triggers exclusion" {
  create_project "Code/My-Project" "custom.config" ".custom-deps"
  write_config "[sentinels]
extra = .custom-deps custom.config"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/.custom-deps"
}

@test "config: disabled sentinel pair is skipped" {
  create_project "Code/My-Project" "package.json" "node_modules"
  write_config "[sentinels]
disabled = node_modules package.json"
  run_asimov
  refute_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "config: glob sentinel from config does not allow shell injection" {
  # A malicious glob sentinel must not be able to run arbitrary commands when
  # interpolated into the find -execdir sh -c check (S1 regression test).
  local pwned="${BATS_TEST_TMPDIR:-$HOME}/pwned"
  rm -f "$pwned"
  create_project "Code/My-Project" "trigger.x" ".custom-deps"
  write_config "[sentinels]
extra = .custom-deps *.x'; touch ${pwned}; '"
  run_asimov --full-scan
  [[ ! -e "$pwned" ]]
}

# =============================================================================
# Summary output
# =============================================================================

@test "prints summary with count when directories are excluded" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov
  [[ "$output" == *"Excluded 2 directories"* ]]
  [[ "$output" != *"totalling"* ]]
}

@test "prints summary with count and total size when --stats is set" {
  create_project "Code/Project-A" "package.json" "node_modules"
  create_project "Code/Project-B" "composer.json" "vendor"
  run_asimov --stats
  [[ "$output" == *"Excluded 2 directories"* ]]
  [[ "$output" == *"totalling"* ]]
  [[ "$output" =~ totalling\ .*[KMG]\. ]]
}

@test "prints no-exclusion message when nothing to exclude" {
  run_asimov
  [[ "$output" == *"No new directories to exclude"* ]]
}

@test "prints no-exclusion message when all directories already excluded" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"

  # Simulate mdfind reporting the already-excluded path (as real macOS would)
  ASIMOV_TEST_MDFIND_RESULTS="${TEST_TEMP_DIR}/.mdfind_results"
  export ASIMOV_TEST_MDFIND_RESULTS
  echo "${HOME}/Code/My-Project/node_modules" > "$ASIMOV_TEST_MDFIND_RESULTS"

  # Run again — everything is already excluded and filtered by cache lookup
  run_asimov
  [[ "$output" == *"No new directories to exclude"* ]]
}

# =============================================================================
# Error handling
# =============================================================================

@test "continues when tmutil fails for a path" {
  create_project "Code/Good-Project" "package.json" "node_modules"
  create_project "Code/Bad-Project" "Cargo.toml" "target"

  # Mark the bad project as one that will cause tmutil to fail
  ASIMOV_TEST_TMUTIL_FAIL_PATHS="${TEST_TEMP_DIR}/.tmutil_fail_paths"
  export ASIMOV_TEST_TMUTIL_FAIL_PATHS
  echo "${HOME}/Code/Bad-Project/target" > "$ASIMOV_TEST_TMUTIL_FAIL_PATHS"

  run_asimov

  # The good project should still be excluded
  assert_excluded "${HOME}/Code/Good-Project/node_modules"
  # The bad project should NOT be in the exclusions list
  refute_excluded "${HOME}/Code/Bad-Project/target"
  [[ "$(count_exclusions)" -eq 1 ]]
}

@test "prints warning when tmutil fails" {
  create_project "Code/Bad-Project" "package.json" "node_modules"

  ASIMOV_TEST_TMUTIL_FAIL_PATHS="${TEST_TEMP_DIR}/.tmutil_fail_paths"
  export ASIMOV_TEST_TMUTIL_FAIL_PATHS
  echo "${HOME}/Code/Bad-Project/node_modules" > "$ASIMOV_TEST_TMUTIL_FAIL_PATHS"

  run_asimov

  # Script should succeed (exit 0) even though tmutil failed
  [[ "$status" -eq 0 ]]
  # Output should contain the warning
  [[ "$output" == *"failed to exclude"* ]]
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "does not leak tmutil's POSIXError dump into output" {
  create_project "Code/Bad-Project" "package.json" "node_modules"

  ASIMOV_TEST_TMUTIL_FAIL_PATHS="${TEST_TEMP_DIR}/.tmutil_fail_paths"
  export ASIMOV_TEST_TMUTIL_FAIL_PATHS
  echo "${HOME}/Code/Bad-Project/node_modules" > "$ASIMOV_TEST_TMUTIL_FAIL_PATHS"

  run_asimov

  [[ "$status" -eq 0 ]]
  # tmutil dumps POSIXError(...) to stdout — not stderr — so a bare 2>/dev/null
  # lets it leak. Asimov must swallow it and print its own warning instead.
  [[ "$output" != *"POSIXError"* ]]
  [[ "$output" == *"failed to exclude"* ]]
}

# =============================================================================
# Read-only directories (e.g. Go's module cache, which is 0555)
# =============================================================================

@test "skips read-only directory without attempting tmutil" {
  create_project "Code/Go-Project" "go.mod" "vendor"
  chmod 555 "${HOME}/Code/Go-Project/vendor"

  run_asimov
  local status_copy="$status" output_copy="$output"
  chmod 755 "${HOME}/Code/Go-Project/vendor"

  [[ "$status_copy" -eq 0 ]]
  refute_excluded "${HOME}/Code/Go-Project/vendor"
  # The read-only pre-check should fire — NOT the tmutil-failure path. A Time
  # Machine exclusion is an xattr on the item, so a 0555 dir can never take one.
  [[ "$output_copy" == *"read-only"* ]]
  [[ "$output_copy" != *"tmutil error"* ]]
}

@test "read-only directory is recorded in failed state" {
  create_project "Code/Go-Project" "go.mod" "vendor"
  chmod 555 "${HOME}/Code/Go-Project/vendor"

  run_asimov
  chmod 755 "${HOME}/Code/Go-Project/vendor"

  assert_failed "${HOME}/Code/Go-Project/vendor"
}

@test "writable directory containing @ is excluded (@ is not the blocker)" {
  # Regression guard: the failure on Go module paths was long attributed to the
  # '@' in the version syntax. It is not — read-only permissions are the cause.
  create_project "Code/cheat@v0.0.0-20211009161301" "go.mod" "vendor"

  run_asimov

  assert_excluded "${HOME}/Code/cheat@v0.0.0-20211009161301/vendor"
}

# =============================================================================
# --help, --version, unknown option
# =============================================================================

@test "help option prints usage and exits 0" {
  run_asimov --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"asimov"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--verbose"* ]]
  [[ "$output" == *"--quiet"* ]]
}

@test "version option prints version and exits 0" {
  expected_version="$(grep '^readonly ASIMOV_VERSION=' "${BATS_TEST_DIRNAME}/../asimov" | cut -d"'" -f2)"
  run_asimov --version
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"$expected_version"* ]]
}

@test "unknown option exits 1 and prints error" {
  run_asimov --unknown
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"unknown option"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "scans a specified directory instead of home" {
  create_project "Code/My-Project" "package.json" "node_modules"
  mkdir -p "${HOME}/Other-Project"
  run_asimov "${HOME}/Code"
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "exits with error for non-existent directory argument" {
  run_asimov /does/not/exist
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "not a directory" ]]
}

# =============================================================================
# [scan] extra — scan directories beyond home
# =============================================================================

@test "config [scan] extra scans an additional directory alongside home" {
  local external
  external="$(mktemp -d)"
  mkdir -p "${external}/Site/node_modules"
  echo "sentinel" > "${external}/Site/package.json"
  create_project "Code/Home-Project" "package.json" "node_modules"

  write_config "[scan]
extra = ${external}"

  run_asimov
  assert_excluded "${HOME}/Code/Home-Project/node_modules"
  assert_excluded "${external}/Site/node_modules"

  rm -rf "$external"
}

@test "config [scan] extra with a missing directory warns and keeps scanning home" {
  create_project "Code/Home-Project" "package.json" "node_modules"

  write_config "[scan]
extra = /does/not/exist"

  run_asimov
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "does not exist" ]]
  assert_excluded "${HOME}/Code/Home-Project/node_modules"
}

@test "directory argument overrides config [scan] extra" {
  local external
  external="$(mktemp -d)"
  mkdir -p "${external}/Site/node_modules"
  echo "sentinel" > "${external}/Site/package.json"
  create_project "Code/Home-Project" "package.json" "node_modules"

  write_config "[scan]
extra = ${external}"

  # Explicit path scans only that path; the configured extra dir is ignored.
  run_asimov "${HOME}/Code"
  assert_excluded "${HOME}/Code/Home-Project/node_modules"
  refute_excluded "${external}/Site/node_modules"

  rm -rf "$external"
}

@test "config [scan] extra nested under home is pruned, not scanned twice" {
  create_project "Code/Home-Project" "package.json" "node_modules"

  # ~/Code is already covered by the home scan; listing it must not cause a
  # duplicate exclusion of the same directory.
  write_config "[scan]
extra = ${HOME}/Code"

  run_asimov
  assert_excluded "${HOME}/Code/Home-Project/node_modules"
  [[ "$(count_exclusions)" -eq 1 ]]
}

# =============================================================================
# --verbose
# =============================================================================

@test "default output hides already-excluded messages" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"

  # Simulate mdfind reporting the already-excluded path
  ASIMOV_TEST_MDFIND_RESULTS="${TEST_TEMP_DIR}/.mdfind_results"
  export ASIMOV_TEST_MDFIND_RESULTS
  echo "${HOME}/Code/My-Project/node_modules" > "$ASIMOV_TEST_MDFIND_RESULTS"

  # Run again — directory is already excluded but message is hidden without --verbose
  run_asimov
  [[ "$output" != *"already excluded"* ]]
}

@test "verbose shows already-excluded messages" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov
  assert_excluded "${HOME}/Code/My-Project/node_modules"

  # Simulate mdfind reporting the already-excluded path
  ASIMOV_TEST_MDFIND_RESULTS="${TEST_TEMP_DIR}/.mdfind_results"
  export ASIMOV_TEST_MDFIND_RESULTS
  echo "${HOME}/Code/My-Project/node_modules" > "$ASIMOV_TEST_MDFIND_RESULTS"

  # Run again with --verbose
  run_asimov --verbose
  [[ "$output" == *"already excluded"* ]]
}

# =============================================================================
# --quiet
# =============================================================================

@test "quiet mode suppresses all non-error output" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --quiet
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  assert_excluded "${HOME}/Code/My-Project/node_modules"
}

@test "quiet mode still shows errors on stderr" {
  create_project "Code/Bad-Project" "package.json" "node_modules"

  ASIMOV_TEST_TMUTIL_FAIL_PATHS="${TEST_TEMP_DIR}/.tmutil_fail_paths"
  export ASIMOV_TEST_TMUTIL_FAIL_PATHS
  echo "${HOME}/Code/Bad-Project/node_modules" > "$ASIMOV_TEST_TMUTIL_FAIL_PATHS"

  run_asimov --quiet
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"failed to exclude"* ]]
}

@test "quiet and verbose together exits with error" {
  run_asimov --quiet --verbose
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"mutually exclusive"* ]]
}

# =============================================================================
# Flag combinations
# =============================================================================

@test "dry-run with verbose shows would-exclude messages" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run --verbose
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Would exclude"* ]]
  [[ "$output" == *"node_modules"* ]]
}

@test "dry-run with quiet suppresses output" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run --quiet
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

# =============================================================================
# --dry-run
# =============================================================================

@test "dry-run prints would-exclude but does not call tmutil" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Would exclude"* ]]
  [[ "$output" == *"node_modules"* ]]
  [[ "$output" == *"Would exclude"*"directories"* ]]
  [[ "$output" != *"totalling"* ]]
  # Mock tmutil should not have recorded any exclusion
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "dry-run with --stats shows size in per-path output and total" {
  create_project "Code/My-Project" "package.json" "node_modules"
  run_asimov --dry-run --stats
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Would exclude"* ]]
  [[ "$output" == *"totalling"* ]]
  [[ "$output" =~ totalling\ [0-9]+[KMG]\. ]]
  [[ "$(count_exclusions)" -eq 0 ]]
}

# Issue #19: --dry-run must run the same tmutil isexcluded ground-truth guard as
# a real run, so its preview never claims it would exclude a path that Time
# Machine already covers via an excluded ancestor (e.g. a manually excluded
# ~/.nvm). Such exclusions are often path-based and NOT reported by Spotlight,
# so the Layer-1 cache misses them and only the Layer-3 guard catches them.

@test "dry-run does not list a dependency dir already covered by an excluded ancestor (issue #19)" {
  create_project "Projects/app" "package.json" "node_modules"
  # Manual Time Machine exclusion of the parent that Spotlight does not report.
  echo "${HOME}/Projects/app" > "$ASIMOV_TEST_EXCLUSIONS"

  run_asimov --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"Would exclude: ${HOME}/Projects/app/node_modules"* ]]
  [[ "$output" == *"No directories would be excluded."* ]]
}

@test "dry-run lists a not-yet-excluded dependency dir without excluding it" {
  create_project "Projects/app" "package.json" "node_modules"
  run_asimov --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Would exclude: ${HOME}/Projects/app/node_modules"* ]]
  refute_excluded "${HOME}/Projects/app/node_modules"
}

@test "real run skips a dependency dir already covered by an excluded ancestor (dry-run parity)" {
  create_project "Projects/app" "package.json" "node_modules"
  echo "${HOME}/Projects/app" > "$ASIMOV_TEST_EXCLUSIONS"

  run_asimov
  [[ "$status" -eq 0 ]]
  # Only the pre-existing parent exclusion remains; node_modules is not re-added.
  [[ "$(count_exclusions)" -eq 1 ]]
  refute_excluded "${HOME}/Projects/app/node_modules"
}

# =============================================================================
# Glob support in fixed directories
# =============================================================================

@test "fixed dirs: extra path expands a glob" {
  mkdir -p "${HOME}/builds/alpha/dist"
  mkdir -p "${HOME}/builds/beta/dist"
  write_config "[fixed_dirs]
extra = ~/builds/*/dist"

  run_asimov

  assert_excluded "${HOME}/builds/alpha/dist"
  assert_excluded "${HOME}/builds/beta/dist"
}

@test "fixed dirs: glob expansion keeps paths containing spaces intact" {
  mkdir -p "${HOME}/Application Support/My App/Code Cache"
  write_config "[fixed_dirs]
extra = ~/Application Support/*/Code Cache"

  run_asimov

  assert_excluded "${HOME}/Application Support/My App/Code Cache"
}

@test "fixed dirs: glob matching nothing is not an error" {
  write_config "[fixed_dirs]
extra = ~/nowhere/*/dist"

  run_asimov

  [[ "$status" -eq 0 ]]
  [[ "$(count_exclusions)" -eq 0 ]]
}

@test "fixed dirs: glob only matches directories, not files" {
  mkdir -p "${HOME}/builds/alpha"
  touch "${HOME}/builds/alpha/dist"
  write_config "[fixed_dirs]
extra = ~/builds/*/dist"

  run_asimov

  [[ "$status" -eq 0 ]]
  refute_excluded "${HOME}/builds/alpha/dist"
}

# =============================================================================
# Application caches
# =============================================================================

# Create a directory under ~/Library/Application Support.
create_app_support_dir() {
  mkdir -p "${HOME}/Library/Application Support/$1"
}

# Simulate a machine that has already run an earlier version of Asimov.
simulate_prior_install() {
  mkdir -p "${HOME}/.cache/asimov"
  echo "${HOME}/some/old/path" > "${HOME}/.cache/asimov/excluded"
}

@test "app caches: excluded by default on a new install" {
  create_app_support_dir "Spotify/PersistentCache"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

@test "app caches: matches a named cache one level below Application Support" {
  create_app_support_dir "discord/Cache"
  create_app_support_dir "Code/CachedExtensionVSIXs"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/discord/Cache"
  assert_excluded "${HOME}/Library/Application Support/Code/CachedExtensionVSIXs"
}

@test "app caches: matches a named cache two levels below Application Support" {
  create_app_support_dir "Arc/User Data/Code Cache"
  create_app_support_dir "Google/Chrome/component_crx_cache"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Arc/User Data/Code Cache"
  assert_excluded "${HOME}/Library/Application Support/Google/Chrome/component_crx_cache"
}

@test "app caches: leaves non-cache directories alone" {
  create_app_support_dir "Code/User"
  create_app_support_dir "Google/Chrome/Default"
  run_asimov
  refute_excluded "${HOME}/Library/Application Support/Code/User"
  refute_excluded "${HOME}/Library/Application Support/Google/Chrome/Default"
}

@test "app caches: not excluded when the machine has prior Asimov state" {
  simulate_prior_install
  create_app_support_dir "Spotify/PersistentCache"
  run_asimov
  refute_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

@test "app caches: existing user can opt in explicitly" {
  simulate_prior_install
  create_app_support_dir "Spotify/PersistentCache"
  write_config "[app_caches]
enabled = true"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

@test "app caches: new install can opt out explicitly" {
  create_app_support_dir "Spotify/PersistentCache"
  write_config "[app_caches]
enabled = false"
  run_asimov
  refute_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

@test "app caches: first run records the resolved default" {
  run_asimov
  [[ -f "${HOME}/.local/state/asimov/profile" ]]
  grep -qx 'app_caches_default=true' "${HOME}/.local/state/asimov/profile"
}

@test "app caches: an upgrader's recorded default is off" {
  simulate_prior_install
  run_asimov
  grep -qx 'app_caches_default=false' "${HOME}/.local/state/asimov/profile"
}

@test "app caches: recorded default survives a cache wipe" {
  # Existing user: default resolves to off and is recorded.
  simulate_prior_install
  run_asimov
  grep -qx 'app_caches_default=false' "${HOME}/.local/state/asimov/profile"

  # Wiping the cache would otherwise make them look like a new install.
  rm -rf "${HOME}/.cache/asimov"
  create_app_support_dir "Spotify/PersistentCache"
  run_asimov

  refute_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

@test "app caches: dry-run does not record a default" {
  run_asimov --dry-run
  [[ "$status" -eq 0 ]]
  [[ ! -f "${HOME}/.local/state/asimov/profile" ]]
}

@test "app caches: --no-write-cache does not record a default" {
  run_asimov --no-write-cache
  [[ "$status" -eq 0 ]]
  [[ ! -f "${HOME}/.local/state/asimov/profile" ]]
}

@test "app caches: a full scan by an existing user still counts as an upgrade" {
  # --no-read-cache clears the state files, so the prior-install signal must be
  # captured before that happens.
  simulate_prior_install
  create_app_support_dir "Spotify/PersistentCache"
  run_asimov --full-scan
  refute_excluded "${HOME}/Library/Application Support/Spotify/PersistentCache"
}

# =============================================================================
# Application caches: service-worker caches
# =============================================================================

@test "app caches: excludes the service-worker CacheStorage" {
  create_app_support_dir "Asana/Service Worker/CacheStorage"
  create_app_support_dir "Google/Chrome/Default/Service Worker/CacheStorage"
  create_app_support_dir "Arc/User Data/Profile 3/Service Worker/CacheStorage"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Asana/Service Worker/CacheStorage"
  assert_excluded "${HOME}/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"
  assert_excluded "${HOME}/Library/Application Support/Arc/User Data/Profile 3/Service Worker/CacheStorage"
}

@test "app caches: excludes the service-worker ScriptCache" {
  create_app_support_dir "Asana/Service Worker/ScriptCache"
  create_app_support_dir "Google/Chrome/Default/Service Worker/ScriptCache"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Asana/Service Worker/ScriptCache"
  assert_excluded "${HOME}/Library/Application Support/Google/Chrome/Default/Service Worker/ScriptCache"
}

@test "app caches: leaves the service-worker registration database alone" {
  # Database/ holds the registrations. Losing it logs you out of web apps and
  # drops their offline mode, so only the cache siblings are excluded.
  create_app_support_dir "Asana/Service Worker/CacheStorage"
  create_app_support_dir "Asana/Service Worker/Database"
  run_asimov
  refute_excluded "${HOME}/Library/Application Support/Asana/Service Worker"
  refute_excluded "${HOME}/Library/Application Support/Asana/Service Worker/Database"
}

@test "app caches: excludes Claude Desktop's sandbox images" {
  create_app_support_dir "Claude/vm_bundles"
  run_asimov
  assert_excluded "${HOME}/Library/Application Support/Claude/vm_bundles"
}

@test "app caches: service-worker caches respect the opt-out" {
  create_app_support_dir "Asana/Service Worker/CacheStorage"
  create_app_support_dir "Claude/vm_bundles"
  write_config "[app_caches]
enabled = false"
  run_asimov
  refute_excluded "${HOME}/Library/Application Support/Asana/Service Worker/CacheStorage"
  refute_excluded "${HOME}/Library/Application Support/Claude/vm_bundles"
}
