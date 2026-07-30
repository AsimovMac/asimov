#!/usr/bin/env bats
#
# Schema tests for the data entities in data/*.tsv.
#
# These files are edited by contributors who may never open a .sh file, so the
# failure modes are spaces instead of tabs, a missing field, or a duplicate row.
# None of those are visible in a diff; all of them are caught here.

load test_helper

data_dir() {
  echo "${BATS_TEST_DIRNAME}/../data"
}

# Every non-comment, non-blank row of a data file.
data_rows() {
  grep -v '^#' "$(data_dir)/$1" | grep -v '^[[:space:]]*$' || true
}

# =============================================================================
# sentinels.tsv
# =============================================================================

@test "sentinels.tsv: every row has at least dir, sentinel and ecosystem" {
  local bad
  bad="$(data_rows sentinels.tsv | awk -F'\t' 'NF < 3 || $1 == "" || $2 == "" || $3 == ""')"
  [[ -z "$bad" ]] || {
    echo "Rows with fewer than 3 tab-separated fields (spaces instead of tabs?):" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "sentinels.tsv: no field contains a space" {
  # A space in dir or sentinel would break the "dir sentinel" pair string the
  # config file and find both speak in.
  local bad
  bad="$(data_rows sentinels.tsv | awk -F'\t' '$1 ~ / / || $2 ~ / / || $3 ~ / /')"
  [[ -z "$bad" ]] || {
    echo "Rows with a space inside dir, sentinel or ecosystem:" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "sentinels.tsv: no duplicate dir + sentinel pair" {
  local dupes
  dupes="$(data_rows sentinels.tsv | awk -F'\t' '{print $1" "$2}' | sort | uniq -d)"
  [[ -z "$dupes" ]] || {
    echo "Duplicate pairs:" >&2
    echo "$dupes" >&2
    return 1
  }
}

@test "sentinels.tsv: ecosystem is lowercase" {
  local bad
  bad="$(data_rows sentinels.tsv | awk -F'\t' '$3 ~ /[A-Z]/')"
  [[ -z "$bad" ]] || {
    echo "Rows with an uppercase ecosystem:" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "sentinels.tsv: every row reaches the find expression" {
  # The count the script actually loads must match the count in the file: a row
  # dropped by the loader would otherwise be invisible.
  local in_file
  in_file="$(data_rows sentinels.tsv | wc -l | tr -d ' ')"

  run_asimov doctor
  [[ "$output" == *"${in_file} sentinels"* ]]
}

# =============================================================================
# fixed-dirs.tsv
# =============================================================================

@test "fixed-dirs.tsv: every row has a path and a tool" {
  local bad
  bad="$(data_rows fixed-dirs.tsv | awk -F'\t' 'NF < 2 || $1 == "" || $2 == ""')"
  [[ -z "$bad" ]] || {
    echo "Rows with fewer than 2 tab-separated fields:" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "fixed-dirs.tsv: paths are relative to the root, never absolute or ~" {
  # The loader prefixes $ASIMOV_ROOT, so an absolute path or a ~ would produce
  # a nonsense path like /Users/me//usr/local.
  local bad
  bad="$(data_rows fixed-dirs.tsv | awk -F'\t' '$1 ~ /^[\/~]/ || $1 ~ /\$/')"
  [[ -z "$bad" ]] || {
    echo "Rows whose path is absolute, starts with ~, or interpolates a variable:" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "fixed-dirs.tsv: no duplicate paths" {
  local dupes
  dupes="$(data_rows fixed-dirs.tsv | awk -F'\t' '{print $1}' | sort | uniq -d)"
  [[ -z "$dupes" ]] || {
    echo "Duplicate paths:" >&2
    echo "$dupes" >&2
    return 1
  }
}

# =============================================================================
# skip-paths.tsv
# =============================================================================

@test "skip-paths.tsv: every row has a path and a reason" {
  local bad
  bad="$(data_rows skip-paths.tsv | awk -F'\t' 'NF < 2 || $1 == "" || $2 == ""')"
  [[ -z "$bad" ]] || {
    echo "Rows with fewer than 2 tab-separated fields:" >&2
    echo "$bad" >&2
    return 1
  }
}

@test "skip-paths.tsv: paths are relative to the root" {
  local bad
  bad="$(data_rows skip-paths.tsv | awk -F'\t' '$1 ~ /^[\/~]/ || $1 ~ /\$/')"
  [[ -z "$bad" ]] || {
    echo "Rows whose path is absolute, starts with ~, or interpolates a variable:" >&2
    echo "$bad" >&2
    return 1
  }
}

# =============================================================================
# Loader behaviour
# =============================================================================

@test "a missing data file aborts the run with a clear message" {
  local empty="${TEST_TEMP_DIR}/empty-data"
  mkdir -p "$empty"

  run env ASIMOV_DATA="$empty" "${ASIMOV_CMD[@]}" --dry-run

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"missing data file"* ]]
  [[ "$output" == *"sentinels.tsv"* ]]
}

@test "doctor reports a missing data file instead of aborting" {
  local empty="${TEST_TEMP_DIR}/empty-data"
  mkdir -p "$empty"

  run env ASIMOV_DATA="$empty" "${ASIMOV_CMD[@]}" doctor

  # doctor has to survive a broken install: that is when it is most needed.
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"missing data file"* ]]
  [[ "$output" == *"Reinstall asimov"* ]]
}

@test "a sentinel added to the data file is honoured without touching any script" {
  local custom="${TEST_TEMP_DIR}/custom-data"
  mkdir -p "$custom"
  cp "$(data_dir)/fixed-dirs.tsv" "$(data_dir)/skip-paths.tsv" "$custom/"
  printf 'widgets\twidget.toml\twidgetlang\tinvented for this test\n' > "${custom}/sentinels.tsv"

  create_project "Code/Widget-Project" "widget.toml" "widgets"
  create_project "Code/Node-Project" "package.json" "node_modules"

  run env ASIMOV_DATA="$custom" "${ASIMOV_CMD[@]}"
  [[ "$status" -eq 0 ]]

  assert_excluded "${HOME}/Code/Widget-Project/widgets"
  # The built-in list was replaced, not merged, so node_modules is not matched.
  refute_excluded "${HOME}/Code/Node-Project/node_modules"
}
