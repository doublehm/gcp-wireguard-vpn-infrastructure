# shellcheck shell=bash
# state.sh — persistent KEY=value state in the user's config dir.

state_dir() {
  printf '%s\n' "${WG_HUB_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/wg-hub}"
}

state_init() {
  local d
  d="$(state_dir)"
  mkdir -p "$d"
  chmod 700 "$d"
}

state_get() {
  local f
  f="$(state_dir)/state"
  [ -f "$f" ] || return 0
  awk -v k="$1" 'index($0, k "=") == 1 { v = substr($0, length(k) + 2) } END { if (v != "") print v }' "$f"
}

state_set() {
  local key="$1" value="$2" f tmp
  state_init
  f="$(state_dir)/state"
  tmp="$f.tmp.$$"
  (
    umask 077
    if [ -f "$f" ]; then
      awk -v k="$1" 'index($0, k "=") != 1' "$f"
    fi
    printf '%s=%s\n' "$key" "$value"
  ) >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$f"
}

require_state() {
  [ -n "$(state_get HUB_PUBKEY)" ] || die 'No hub configured. Run `wg-hub setup` first.'
}
