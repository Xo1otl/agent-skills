#!/usr/bin/env bash
set -u

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly NOTIFIER="$TEST_DIR/../scripts/codex_notifier.sh"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local name=$1
  local output=$2
  local expected=$3
  [[ $output == *"$expected"* ]] || fail "$name: missing '$expected'"
}

parse_multiple_windows() (
  source "$NOTIFIER"
  parse_rate_limits '{
    "rateLimits": {
      "primary": {"usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1787643470},
      "secondary": {"usedPercent": 87, "windowDurationMins": 10080, "resetsAt": 1788248270}
    }
  }'
  printf '%s|%s\n' "$current_used" "$current_window"
)

rolling_recovery() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '2026-08-21 01:00 UTC' '5-hour window'
  handle_usage 84 '2026-08-21 01:00 UTC' '5-hour window'
)

mid_unit_escalation() (
  source "$NOTIFIER"
  after_unit=85
  mid_unit=95

  handle_usage 86 '2026-08-21 01:00 UTC' '5-hour window'
  handle_usage 96 '2026-08-21 01:00 UTC' '5-hour window'
  handle_usage 99 '2026-08-21 01:00 UTC' '5-hour window'
)

output=$(parse_multiple_windows)
[[ $output == '87|7-day window' ]] || fail "window selection: got '$output'"

output=$(rolling_recovery)
assert_contains 'rolling recovery' "$output" 'Finish the current unit of work'
assert_contains 'rolling recovery' "$output" 'Resume work'

output=$(mid_unit_escalation)
assert_contains 'mid-unit escalation' "$output" 'Finish the current unit of work'
assert_contains 'mid-unit escalation' "$output" 'Stop the current unit of work immediately'
lines=$(printf '%s\n' "$output" | wc -l)
[[ $lines == 2 ]] || fail "mid-unit escalation: expected 2 lines, got $lines"

if ((failures > 0)); then
  exit 1
fi

printf 'ok - Codex notifier\n'
