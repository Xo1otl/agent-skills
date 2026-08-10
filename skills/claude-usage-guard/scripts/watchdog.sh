#!/usr/bin/env bash
set -u

graceful=90
force=98
interval=60

last_reset=""
graceful_sent=0
force_sent=0
poll_failed=0

usage() {
  printf '%s\n' \
    'Usage: watchdog.sh [--graceful PERCENT] [--force PERCENT] [--interval SECONDS]'
}

fail() {
  printf 'claude-usage-guard: %s\n' "$1" >&2
  exit 2
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --graceful | --force | --interval)
        (($# >= 2)) || fail "$1 requires a value"
        case "$1" in
          --graceful) graceful=$2 ;;
          --force) force=$2 ;;
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

  [[ $graceful =~ ^[0-9]+$ ]] || fail '--graceful must be an integer from 0 to 99'
  [[ $force =~ ^[0-9]+$ ]] || fail '--force must be an integer from 1 to 100'
  [[ $interval =~ ^[0-9]+$ ]] || fail '--interval must be a positive integer'

  graceful=$((10#$graceful))
  force=$((10#$force))
  interval=$((10#$interval))

  ((graceful >= 0 && graceful < force && force <= 100)) ||
    fail 'thresholds must satisfy 0 <= graceful < force <= 100'
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

emit_graceful_stop() {
  printf 'The usage quota for the current five-hour window is %s%% consumed and resets at %s. Finish the current unit of work, then pause until the quota resets.\n' \
    "$1" "$2"
}

emit_force_stop() {
  printf 'The usage quota for the current five-hour window is %s%% consumed and resets at %s. Pause immediately until the quota resets.\n' \
    "$1" "$2"
}

emit_resume() {
  printf '%s\n' 'The usage quota has reset. Resume the paused loop.'
}

handle_usage() {
  local used=$1
  local reset=$2

  if [[ -n $last_reset && $reset != "$last_reset" ]]; then
    if ((graceful_sent || force_sent)); then
      emit_resume
    fi
    graceful_sent=0
    force_sent=0
  fi
  last_reset=$reset

  if ((used >= force)); then
    if ((!force_sent)); then
      emit_force_stop "$used" "$reset"
      graceful_sent=1
      force_sent=1
    fi
  elif ((used >= graceful && !graceful_sent)); then
    emit_graceful_stop "$used" "$reset"
    graceful_sent=1
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
