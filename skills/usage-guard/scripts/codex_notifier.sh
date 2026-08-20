#!/usr/bin/env bash
set -u

readonly PROGRAM="${USAGE_GUARD_PROGRAM:-${BASH_SOURCE[0]##*/}}"
readonly STATE_ACTIVE=0
readonly STATE_AFTER_UNIT=1
readonly STATE_MID_UNIT=2
readonly RESPONSE_TIMEOUT=15

after_unit=""
mid_unit=""
interval=""

stop_state=$STATE_ACTIVE
poll_failed=0
server_pid=""
server_read_fd=""
server_write_fd=""
next_request_id=2
response_result=""

usage() {
  printf '%s\n' \
    "Usage: $PROGRAM --after-unit PERCENT --mid-unit PERCENT --interval SECONDS" \
    '' \
    '  --after-unit PERCENT  usage threshold at which to end the turn after the current unit of work' \
    '  --mid-unit PERCENT    usage threshold at which to end the turn immediately, even mid-unit' \
    '  --interval SECONDS    how often to poll Codex rate limits, in seconds'
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

format_reset() {
  local reset=$1
  local formatted

  if [[ $reset == - ]]; then
    printf 'at an unknown time'
  elif formatted=$(date -u --date="@$reset" '+%Y-%m-%d %H:%M UTC' 2>/dev/null); then
    printf '%s' "$formatted"
  else
    printf 'at epoch %s' "$reset"
  fi
}

format_window() {
  local duration=$1
  local kind=$2

  if [[ $duration == - ]]; then
    printf '%s window' "$kind"
  elif ((duration % 1440 == 0)); then
    printf '%s-day window' "$((duration / 1440))"
  elif ((duration % 60 == 0)); then
    printf '%s-hour window' "$((duration / 60))"
  else
    printf '%s-minute window' "$duration"
  fi
}

parse_rate_limits() {
  local payload=$1
  local record used reset duration kind

  record=$(jq -er '
    (.rateLimitsByLimitId.codex // .rateLimits) as $limit
    | [
        {kind: "primary", window: $limit.primary},
        {kind: "secondary", window: $limit.secondary}
      ]
    | map(select(.window != null and ((.window.usedPercent | type) == "number")))
    | if length == 0 then empty else max_by(.window.usedPercent) end
    | [
        (.window.usedPercent | tostring),
        ((.window.resetsAt // "-") | tostring),
        ((.window.windowDurationMins // "-") | tostring),
        .kind
      ]
    | @tsv
  ' <<<"$payload" 2>/dev/null) || return 1

  IFS=$'\t' read -r used reset duration kind <<<"$record"
  [[ $used =~ ^[0-9]+$ ]] || return 1
  [[ $reset == - || $reset =~ ^[0-9]+$ ]] || return 1
  [[ $duration == - || $duration =~ ^[0-9]+$ ]] || return 1
  ((used <= 100)) || return 1

  current_used=$((10#$used))
  current_reset=$(format_reset "$reset")
  current_window=$(format_window "$duration" "$kind")
}

stop_server() {
  if [[ $server_write_fd =~ ^[0-9]+$ ]]; then
    exec {server_write_fd}>&- 2>/dev/null || true
  fi
  if [[ $server_read_fd =~ ^[0-9]+$ ]]; then
    exec {server_read_fd}<&- 2>/dev/null || true
  fi
  if [[ $server_pid =~ ^[0-9]+$ ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi

  server_pid=""
  server_read_fd=""
  server_write_fd=""
  unset CODEX_APP_SERVER CODEX_APP_SERVER_PID 2>/dev/null || true
}

await_response() {
  local expected_id=$1
  local deadline=$((SECONDS + RESPONSE_TIMEOUT))
  local remaining line response_id

  while ((remaining = deadline - SECONDS, remaining > 0)); do
    IFS= read -r -t "$remaining" -u "$server_read_fd" line || return 1
    response_id=$(jq -r '.id // empty' <<<"$line" 2>/dev/null) || continue
    [[ $response_id == "$expected_id" ]] || continue
    jq -e '.error == null' <<<"$line" >/dev/null 2>&1 || return 1
    response_result=$(jq -c '.result' <<<"$line" 2>/dev/null) || return 1
    [[ $response_result != null ]] || return 1
    return 0
  done

  return 1
}

start_server() {
  stop_server
  coproc CODEX_APP_SERVER { codex app-server --stdio 2>/dev/null; }
  server_pid=$CODEX_APP_SERVER_PID
  server_read_fd=${CODEX_APP_SERVER[0]}
  server_write_fd=${CODEX_APP_SERVER[1]}

  printf '%s\n' \
    '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"usage-guard","version":"1"}}}' \
    >&"$server_write_fd" || return 1
  await_response 1 || return 1
  printf '%s\n' '{"method":"initialized"}' >&"$server_write_fd" || return 1
  next_request_id=2
}

server_running() {
  [[ $server_pid =~ ^[0-9]+$ ]] && kill -0 "$server_pid" 2>/dev/null
}

poll_usage() {
  local request_id

  if ! server_running; then
    start_server || {
      stop_server
      return 1
    }
  fi

  request_id=$next_request_id
  next_request_id=$((next_request_id + 1))
  printf '{"id":%s,"method":"account/rateLimits/read","params":null}\n' \
    "$request_id" >&"$server_write_fd" || {
      stop_server
      return 1
    }
  await_response "$request_id" || {
    stop_server
    return 1
  }
  parse_rate_limits "$response_result"
}

emit_stop() {
  printf '%s Codex %s usage is at %s%%; the window resets %s.\n' "$1" "$2" "$3" "$4"
}

emit_resume() {
  printf 'Resume work; the highest Codex usage window is at %s%% (%s, resets %s).\n' "$1" "$2" "$3"
}

handle_usage() {
  local used=$1
  local reset=$2
  local window=$3

  if ((stop_state != STATE_ACTIVE && used < after_unit)); then
    emit_resume "$used" "$window" "$reset"
    stop_state=$STATE_ACTIVE
  fi

  if ((used >= mid_unit && stop_state != STATE_MID_UNIT)); then
    emit_stop \
      'Stop the current unit of work immediately and end your turn; you will be notified when it is safe to resume.' \
      "$window" "$used" "$reset"
    stop_state=$STATE_MID_UNIT
  elif ((used >= after_unit && stop_state == STATE_ACTIVE)); then
    emit_stop \
      'Finish the current unit of work, then end your turn; you will be notified when it is safe to resume.' \
      "$window" "$used" "$reset"
    stop_state=$STATE_AFTER_UNIT
  fi
}

main() {
  parse_args "$@"
  command -v codex >/dev/null 2>&1 || fail 'codex not found on PATH'
  command -v jq >/dev/null 2>&1 || fail 'jq not found on PATH'

  trap stop_server EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  while true; do
    if poll_usage; then
      poll_failed=0
      handle_usage "$current_used" "$current_reset" "$current_window"
    elif ((!poll_failed)); then
      printf '%s: unable to read Codex rate limits; retrying\n' "$PROGRAM" >&2
      poll_failed=1
    fi
    sleep "$interval"
  done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
