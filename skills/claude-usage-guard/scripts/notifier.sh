#!/usr/bin/env bash
set -u

after_unit=""
mid_unit=""
interval=""

last_reset=""
after_unit_sent=0
mid_unit_sent=0
poll_failed=0

usage() {
  printf '%s\n' \
    'Usage: notifier.sh --after-unit PERCENT --mid-unit PERCENT --interval SECONDS' \
    '' \
    '  --after-unit PERCENT  usage % at which to stop after the current unit of work' \
    '  --mid-unit PERCENT    usage % at which to stop immediately, mid-unit' \
    '  --interval SECONDS    how often to poll /usage'
}

fail() {
  printf 'claude-usage-guard: %s\n' "$1" >&2
  exit 2
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --after-unit | --mid-unit | --interval)
        (($# >= 2)) || fail "$1 requires a value"
        case "$1" in
          --after-unit) after_unit=$2 ;;
          --mid-unit) mid_unit=$2 ;;
          --interval) interval=$2 ;;
        esac
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown argument: $1" ;;
    esac
  done

  [[ -n $after_unit ]] || fail '--after-unit is required'
  [[ -n $mid_unit ]] || fail '--mid-unit is required'
  [[ -n $interval ]] || fail '--interval is required'

  [[ $after_unit =~ ^[0-9]+$ ]] || fail '--after-unit must be an integer from 0 to 99'
  [[ $mid_unit =~ ^[0-9]+$ ]] || fail '--mid-unit must be an integer from 1 to 100'
  [[ $interval =~ ^[0-9]+$ ]] || fail '--interval must be a positive integer'

  after_unit=$((10#$after_unit))
  mid_unit=$((10#$mid_unit))
  interval=$((10#$interval))

  ((after_unit >= 0 && after_unit < mid_unit && mid_unit <= 100)) ||
    fail 'thresholds must satisfy 0 <= after-unit < mid-unit <= 100'
  ((interval > 0)) || fail '--interval must be a positive integer'
}

parse_usage() {
  local payload=$1
  local tail used reset
  local percent='%'
  local escaped_newline='\n'

  [[ $payload == *'Current session: '* ]] || return 1
  tail=${payload#*'Current session: '}
  used=${tail%%"$percent"*}
  [[ $used =~ ^[0-9]+$ ]] || return 1

  [[ $tail == *'resets '* ]] || return 1
  tail=${tail#*'resets '}
  reset=${tail%%"$escaped_newline"*}
  [[ -n $reset && $reset != "$tail" ]] || return 1

  parsed_used=$((10#$used))
  parsed_reset=$reset
}

poll_usage() {
  local payload

  payload=$(env -u CLAUDECODE claude -p '/usage' \
    --safe-mode \
    --output-format json \
    --no-session-persistence 2>/dev/null) || return 1
  parse_usage "$payload"
}

emit_after_unit_stop() {
  printf 'Finish the current unit of work, then end your turn; my next notification will tell you when to resume. Usage is at %s%%; the window resets at %s.\n' \
    "$1" "$2"
}

emit_mid_unit_stop() {
  printf 'Abandon the current unit of work and end your turn; my next notification will tell you when to resume. Usage is at %s%%; the window resets at %s.\n' \
    "$1" "$2"
}

emit_resume() {
  printf '%s\n' 'Resume the loop; the usage window has reset.'
}

handle_usage() {
  local used=$1
  local reset=$2

  if [[ -n $last_reset && $reset != "$last_reset" ]]; then
    if ((after_unit_sent || mid_unit_sent)); then
      emit_resume
    fi
    after_unit_sent=0
    mid_unit_sent=0
  fi
  last_reset=$reset

  if ((used >= mid_unit)); then
    if ((!mid_unit_sent)); then
      emit_mid_unit_stop "$used" "$reset"
      after_unit_sent=1
      mid_unit_sent=1
    fi
  elif ((used >= after_unit && !after_unit_sent)); then
    emit_after_unit_stop "$used" "$reset"
    after_unit_sent=1
  fi
}

main() {
  parse_args "$@"
  command -v claude >/dev/null 2>&1 || fail 'claude is not available on PATH'

  while true; do
    if poll_usage; then
      poll_failed=0
      handle_usage "$parsed_used" "$parsed_reset"
    elif ((!poll_failed)); then
      printf '%s\n' 'claude-usage-guard: unable to read /usage; retrying' >&2
      poll_failed=1
    fi
    sleep "$interval"
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
