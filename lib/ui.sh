# shellcheck shell=bash
# ui.sh — terminal output and prompts.

if [ -t 2 ] && [ -z "${WG_HUB_NO_COLOR:-}" ]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
ok() { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
  printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}
heading() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET" >&2; }

# Read one line from the terminal even when stdin is a pipe (curl | bash).
_read_tty() {
  local __var="$1" __line=''
  local __tty="${WG_HUB_TTY:-/dev/tty}"
  if [ -r "$__tty" ] && { : <"$__tty"; } 2>/dev/null; then
    IFS= read -r __line <"$__tty" || true
  else
    IFS= read -r __line || true
  fi
  printf -v "$__var" '%s' "$__line"
}

# confirm QUESTION — default yes. WG_HUB_YES=1 answers yes.
confirm() {
  [ "${WG_HUB_YES:-}" = 1 ] && return 0
  local ans
  printf '%s? %s [Y/n] ' "$C_YELLOW$C_RESET" "$1" >&2
  _read_tty ans
  case "$ans" in
    '' | y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# prompt QUESTION DEFAULT — echo the answer, DEFAULT on empty input.
prompt() {
  local ans
  if [ "${WG_HUB_YES:-}" = 1 ]; then
    printf '%s\n' "$2"
    return
  fi
  printf '? %s [%s] ' "$1" "$2" >&2
  _read_tty ans
  printf '%s\n' "${ans:-$2}"
}

# step NAME HINT CMD... — run a setup stage. CMD runs outside any `if` so that
# `set -e` stays active inside it; on failure the EXIT trap explains how to resume.
_STEP_NAME=''
_STEP_HINT=''
_step_on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$_STEP_NAME" ]; then
    printf '%s✗ %s failed.%s\n' "$C_RED" "$_STEP_NAME" "$C_RESET" >&2
    [ -n "$_STEP_HINT" ] && printf '  %s\n' "$_STEP_HINT" >&2
    printf '  Re-run `wg-hub setup` to resume.\n' >&2
  fi
}
step() {
  _STEP_NAME="$1"
  _STEP_HINT="$2"
  shift 2
  info "$_STEP_NAME"
  trap _step_on_exit EXIT
  "$@"
  _STEP_NAME=''
}
