#!/usr/bin/env bash
set -u

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly NOTIFIER="$TEST_DIR/../scripts/notifier.sh"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local name=$1 output=$2 expected=$3
  [[ $output == *"$expected"* ]] || fail "$name: missing '$expected'"
}

assert_not_contains() {
  local name=$1 output=$2 unexpected=$3
  [[ $output != *"$unexpected"* ]] || fail "$name: found '$unexpected'"
}

assert_lines() {
  local name=$1 output=$2 expected=$3
  local actual=0

  [[ -z $output ]] || actual=$(printf '%s\n' "$output" | wc -l)
  [[ $actual == "$expected" ]] || fail "$name: expected $expected lines, got $actual"
}

same_window_drop() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '6:30am UTC'
  handle_usage 84 '6:30am UTC'
  handle_usage 87 '6:30am UTC'
)

new_window() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '6:30am UTC'
  handle_usage 0 '11:30am UTC'
)

delayed_new_window() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '6:30am UTC'
  handle_usage 90 '11:30am UTC'
  handle_usage 84 '11:30am UTC'
)

mid_unit_escalation() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '6:30am UTC'
  handle_usage 96 '6:30am UTC'
  handle_usage 99 '6:30am UTC'
)

parse_sample() (
  source "$NOTIFIER"
  parse_usage '{"result":"Current session: 84% used · resets 6:30am UTC\nCurrent week: 12% used"}'
  printf '%s|%s\n' "$parsed_used" "$parsed_reset"
)

output=$(same_window_drop)
assert_lines 'same-window drop' "$output" 1
assert_not_contains 'same-window drop' "$output" 'Resume work'

output=$(new_window)
assert_lines 'new window' "$output" 2
assert_contains 'new window' "$output" 'Resume work'
assert_contains 'new window' "$output" 'available at 0%'

output=$(delayed_new_window)
assert_lines 'delayed new window' "$output" 2
assert_contains 'delayed new window' "$output" 'available at 84%'

output=$(mid_unit_escalation)
assert_lines 'mid-unit escalation' "$output" 2
assert_contains 'mid-unit escalation' "$output" 'Finish the current unit of work'
assert_contains 'mid-unit escalation' "$output" 'Stop the current unit of work immediately'

output=$(parse_sample)
[[ $output == '84|6:30am UTC' ]] || fail "usage parsing: got '$output'"

if ((failures > 0)); then
  exit 1
fi

printf 'ok - notifier state machine\n'
