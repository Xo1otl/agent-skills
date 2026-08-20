#!/usr/bin/env bash
set -u

readonly PROGRAM="${USAGE_GUARD_PROGRAM:-${BASH_SOURCE[0]##*/}}"
readonly STATE_ACTIVE=0
readonly STATE_AFTER_UNIT=1
readonly STATE_MID_UNIT=2

after_unit=""
mid_unit=""
interval=""

stop_state=$STATE_ACTIVE
window_reset=""
poll_failed=0

usage() {
  printf '%s\n' \
    "Usage: $PROGRAM --after-unit PERCENT --mid-unit PERCENT --interval SECONDS" \
    '' \
    '  --after-unit PERCENT  usage threshold at which to end the turn after the current unit of work' \
    '  --mid-unit PERCENT    usage threshold at which to end the turn immediately, even mid-unit' \
    '  --interval SECONDS    how often to poll /usage, in seconds'
}

fail() {
  printf '%s: %s\n' "$PROGRAM" "$1" >&2
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

  ((after_unit <= 99)) || fail '--after-unit must be an integer from 0 to 99'
  ((mid_unit >= 1 && mid_unit <= 100)) || fail '--mid-unit must be an integer from 1 to 100'
  ((after_unit < mid_unit)) || fail '--after-unit must be less than --mid-unit'
  ((interval > 0)) || fail '--interval must be a positive integer'
}

parse_usage() {
  local payload=$1
  local session used reset
  local percent='%'
  local escaped_newline='\n'

  [[ $payload == *'Current session: '* ]] || return 1
  session=${payload#*'Current session: '}
  used=${session%%"$percent"*}
  [[ $used =~ ^[0-9]+$ ]] || return 1

  [[ $session == *'resets '* ]] || return 1
  session=${session#*'resets '}
  reset=${session%%"$escaped_newline"*}
  [[ -n $reset && $reset != "$session" ]] || return 1

  used=$((10#$used))
  ((used <= 100)) || return 1

  parsed_used=$used
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

emit_stop() {
  printf '%s Usage is at %s%%; the window resets %s.\n' "$1" "$2" "$3"
}

emit_resume() {
  printf 'Resume work; a new usage window is available at %s%% and resets %s.\n' "$1" "$2"
}

handle_usage() {
  local used=$1
  local reset=$2

  if ((stop_state == STATE_ACTIVE)); then
    window_reset=$reset
  elif [[ $reset != "$window_reset" ]] && ((used < after_unit)); then
    emit_resume "$used" "$reset"
    stop_state=$STATE_ACTIVE
    window_reset=$reset
  fi

  if ((used >= mid_unit && stop_state != STATE_MID_UNIT)); then
    emit_stop \
      'Stop the current unit of work immediately and end your turn; you will be notified when it is safe to resume.' \
      "$used" "$reset"
    stop_state=$STATE_MID_UNIT
  elif ((used >= after_unit && stop_state == STATE_ACTIVE)); then
    emit_stop \
      'Finish the current unit of work, then end your turn; you will be notified when it is safe to resume.' \
      "$used" "$reset"
    stop_state=$STATE_AFTER_UNIT
  fi
}

main() {
  parse_args "$@"
  command -v claude >/dev/null 2>&1 || fail 'claude not found on PATH'

  while true; do
    if poll_usage; then
      poll_failed=0
      handle_usage "$parsed_used" "$parsed_reset"
    elif ((!poll_failed)); then
      printf '%s: unable to read /usage; retrying\n' "$PROGRAM" >&2
      poll_failed=1
    fi
    sleep "$interval"
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
