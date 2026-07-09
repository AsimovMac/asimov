#!/usr/bin/env bats
#
# Tests for the com.stevegrunwell.asimov.plist LaunchAgent definition.
# Validates that the plist is well-formed and contains the correct values
# required for `brew services start asimov` to schedule correctly.

PLIST_FILE="${BATS_TEST_DIRNAME}/../com.stevegrunwell.asimov.plist"

# =============================================================================
# File existence and validity
# =============================================================================

@test "plist file exists" {
  [[ -f "$PLIST_FILE" ]]
}

@test "plist is valid (plutil -lint)" {
  plutil -lint "$PLIST_FILE"
}

# =============================================================================
# Label
# =============================================================================

@test "plist Label is com.stevegrunwell.asimov" {
  local label
  label="$(plutil -extract Label raw "$PLIST_FILE")"
  [[ "$label" == "com.stevegrunwell.asimov" ]]
}

@test "plist Label matches the filename (without .plist extension)" {
  local label filename_stem
  label="$(plutil -extract Label raw "$PLIST_FILE")"
  filename_stem="$(basename "$PLIST_FILE" .plist)"
  [[ "$label" == "$filename_stem" ]]
}

# =============================================================================
# Program path
# =============================================================================

@test "plist Program is /usr/local/bin/asimov" {
  local program
  program="$(plutil -extract Program raw "$PLIST_FILE")"
  [[ "$program" == "/usr/local/bin/asimov" ]]
}

@test "plist does not use ProgramArguments (uses Program instead)" {
  # ProgramArguments would shadow Program; the plist should use only Program.
  ! plutil -extract ProgramArguments raw "$PLIST_FILE" > /dev/null 2>&1
}

# =============================================================================
# Scheduling (StartInterval)
# =============================================================================

@test "plist uses StartInterval for scheduling" {
  plutil -extract StartInterval raw "$PLIST_FILE" > /dev/null
}

@test "plist StartInterval is 86400 (runs once per day)" {
  local interval
  interval="$(plutil -extract StartInterval raw "$PLIST_FILE")"
  [[ "$interval" -eq 86400 ]]
}

@test "plist does not use StartCalendarInterval" {
  # StartInterval (elapsed seconds) is preferred over cron-style scheduling.
  ! plutil -extract StartCalendarInterval raw "$PLIST_FILE" > /dev/null 2>&1
}

# =============================================================================
# Load behaviour
# =============================================================================

@test "plist does not use RunAtLoad" {
  # RunAtLoad would fire asimov immediately on every login, not just on the interval.
  ! plutil -extract RunAtLoad raw "$PLIST_FILE" > /dev/null 2>&1
}
