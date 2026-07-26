#!/usr/bin/env bash
#
# Run the Bats suite.
#
# Environment:
#   BASH_BIN   pin the bash that runs asimov itself (default: first bash on PATH)
#   BATS_JOBS  run this many tests concurrently (requires GNU parallel)

set -Eeu -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly TEST_FILES=(
    tests/sentinels.bats
    tests/behavior.bats
    tests/cache.bats
    tests/format.bats
    tests/plist.bats
)

# asimov's shebang is #!/usr/bin/env bash, so in real use its interpreter is
# whichever bash comes first on PATH: 3.2 on a stock Mac, 5.x on most development
# machines. They are not equivalent, so the suite has to be runnable under each.
# The helper reads ASIMOV_TEST_BASH and launches asimov with it explicitly, which
# leaves Bats itself running under its own bash.
if [[ -n "${BASH_BIN:-}" ]]; then
    if [[ ! -x "$BASH_BIN" ]]; then
        echo "test.sh: not executable: ${BASH_BIN}" >&2
        exit 1
    fi
    ASIMOV_TEST_BASH="$BASH_BIN"
    export ASIMOV_TEST_BASH
    printf 'Running asimov under %s\n' "$("$BASH_BIN" --version | head -1)"
fi

bats_flags=()
if [[ -n "${BATS_JOBS:-}" ]]; then
    if command -v parallel >/dev/null 2>&1; then
        bats_flags+=(--jobs "$BATS_JOBS")
    else
        echo "test.sh: BATS_JOBS set but GNU parallel is not installed; running serially" >&2
    fi
fi

exec bats ${bats_flags[@]+"${bats_flags[@]}"} "${TEST_FILES[@]}"
