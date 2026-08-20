#!/usr/bin/env bash
set -u

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly NOTIFIER="$TEST_DIR/../scripts/notifier.sh"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_provider() {
  local name=$1
  local expected=$2
  local output

  output=$($name)
  [[ $output == "$expected" ]] || fail "$name: expected $expected, got $output"
}

detect_claude() (
  source "$NOTIFIER"
  unset CODEX_THREAD_ID CODEX_SESSION_ID
  CLAUDECODE=1
  detect_provider
  printf '%s\n' "$provider"
)

detect_codex() (
  source "$NOTIFIER"
  unset CLAUDECODE
  CODEX_THREAD_ID=test
  detect_provider
  printf '%s\n' "$provider"
)

override_ambiguous() (
  source "$NOTIFIER"
  CLAUDECODE=1
  CODEX_SESSION_ID=test
  provider_override=codex
  detect_provider
  printf '%s\n' "$provider"
)

detect_ambiguous() (
  source "$NOTIFIER"
  CLAUDECODE=1
  CODEX_SESSION_ID=test
  detect_provider
)

detect_neither() (
  source "$NOTIFIER"
  unset CLAUDECODE CODEX_THREAD_ID CODEX_SESSION_ID
  detect_provider
)

assert_provider detect_claude claude
assert_provider detect_codex codex
assert_provider override_ambiguous codex

if output=$(detect_ambiguous 2>&1); then
  fail 'ambiguous detection: expected failure'
else
  [[ $output == *'both Claude and Codex environments detected'* ]] ||
    fail "ambiguous detection: unexpected error '$output'"
fi

if output=$(detect_neither 2>&1); then
  fail 'empty detection: expected failure'
else
  [[ $output == *'unable to detect Claude or Codex'* ]] ||
    fail "empty detection: unexpected error '$output'"
fi

output=$(bash "$NOTIFIER" --help)
[[ $output == *'--provider claude|codex'* ]] || fail 'help: provider override is missing'

if ((failures > 0)); then
  exit 1
fi

printf 'ok - notifier dispatch\n'
