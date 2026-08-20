#!/usr/bin/env bash
set -u

readonly PROGRAM="${BASH_SOURCE[0]##*/}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

provider=""
provider_override=""
forward_args=()

usage() {
  printf '%s\n' \
    "Usage: $PROGRAM [--provider claude|codex] --after-unit PERCENT --mid-unit PERCENT --interval SECONDS" \
    '' \
    '  --provider PROVIDER   override automatic provider detection' \
    '  --after-unit PERCENT  usage threshold at which to end the turn after the current unit of work' \
    '  --mid-unit PERCENT    usage threshold at which to end the turn immediately, even mid-unit' \
    '  --interval SECONDS    how often to poll usage, in seconds'
}

fail() {
  printf '%s: %s\n' "$PROGRAM" "$1" >&2
  exit 2
}

parse_dispatch_args() {
  while (($# > 0)); do
    case "$1" in
      --provider)
        (($# >= 2)) || fail '--provider requires a value'
        provider_override=$2
        shift 2
        ;;
      --provider=*)
        provider_override=${1#*=}
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        forward_args+=("$1")
        shift
        ;;
    esac
  done
}

detect_provider() {
  local in_claude=0
  local in_codex=0

  if [[ -n $provider_override ]]; then
    case "$provider_override" in
      claude | codex) provider=$provider_override ;;
      *) fail '--provider must be claude or codex' ;;
    esac
    return
  fi

  [[ -n ${CLAUDECODE:-} ]] && in_claude=1
  if [[ -n ${CODEX_THREAD_ID:-} || -n ${CODEX_SESSION_ID:-} ]]; then
    in_codex=1
  fi

  case "$in_claude:$in_codex" in
    1:0) provider=claude ;;
    0:1) provider=codex ;;
    1:1) fail 'both Claude and Codex environments detected; use --provider' ;;
    0:0) fail 'unable to detect Claude or Codex; use --provider' ;;
  esac
}

main() {
  parse_dispatch_args "$@"
  detect_provider
  USAGE_GUARD_PROGRAM=$PROGRAM exec bash "$SCRIPT_DIR/${provider}_notifier.sh" "${forward_args[@]}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
