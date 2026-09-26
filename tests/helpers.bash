# Shared bats helpers: isolated config dir and a stub bin dir on PATH.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

common_setup() {
  export WG_HUB_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUB_BIN"
  : >"$STUB_LOG"
  export PATH="$STUB_BIN:$PATH"
  export WG_HUB_NO_COLOR=1
  export WG_HUB_TTY=/dev/stdin
}

# stub NAME [BODY] — create an executable that logs its argv then runs BODY.
stub() {
  local name="$1" body="${2:-}"
  cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >>"$STUB_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# load_lib NAME... — source lib files into the test shell.
load_lib() {
  local l
  for l in "$@"; do
    # shellcheck disable=SC1090
    source "$REPO_ROOT/lib/$l.sh"
  done
}

file_mode() {
  if stat -c '%a' "$1" 2>/dev/null; then return; fi
  stat -f '%Lp' "$1"
}
