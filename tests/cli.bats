#!/usr/bin/env bats

load helpers

setup() {
  common_setup
}

@test "no args prints usage and exits 1" {
  run "$REPO_ROOT/wg-hub"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help prints usage and exits 0" {
  run "$REPO_ROOT/wg-hub" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"wg-hub setup"* ]]
}

@test "--version prints version" {
  run "$REPO_ROOT/wg-hub" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^wg-hub\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "unknown command fails" {
  run "$REPO_ROOT/wg-hub" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "add before setup tells user to run setup" {
  run "$REPO_ROOT/wg-hub" add phone
  [ "$status" -eq 1 ]
  [[ "$output" == *"Run \`wg-hub setup\` first"* ]]
}

@test "works when invoked through a symlink" {
  ln -s "$REPO_ROOT/wg-hub" "$STUB_BIN/wg-hub-link"
  run wg-hub-link --version
  [ "$status" -eq 0 ]
}

# --- commands with a configured hub (gcloud/ssh stubbed) ---

configured() {
  export WG_HUB_WG_DIR="$BATS_TEST_TMPDIR/etc-wireguard"
  mkdir -p "$WG_HUB_CONFIG_DIR" && chmod 700 "$WG_HUB_CONFIG_DIR"
  printf 'PROJECT_ID=wg-hub-abc123\nREGION=us-west1\nZONE=us-west1-b\nHUB_IP=203.0.113.7\nHUB_PUBKEY=HUBPUB\nLOCAL_PEER=laptop\nLOCAL_IP=10.66.66.2\n' \
    >"$WG_HUB_CONFIG_DIR/state"
  # Fake hub: answers wg-hub-peer subcommands sent over "gcloud compute ssh".
  stub gcloud '
cmd="${*##*--command=}"
case "$cmd" in
  *used-ips*) echo 10.66.66.2 ;;
  *"wg-hub-peer '"'"'list'"'"'"*) printf "laptop 10.66.66.2 0\r\nphone 10.66.66.3 0\r\n" ;;
esac'
  stub wg 'case "$1" in genkey) echo PRIV ;; pubkey) echo PUB ;; esac'
  stub qrencode 'cat >/dev/null; echo QRCODE'
  stub sudo '"$@"'
}

@test "add allocates the next free IP and writes a private config" {
  configured
  run "$REPO_ROOT/wg-hub" add phone
  [ "$status" -eq 0 ]
  grep -q "wg-hub-peer 'add' 'phone' 'PUB' '10.66.66.3'" "$STUB_LOG"
  conf="$WG_HUB_CONFIG_DIR/peers/phone.conf"
  [ "$(file_mode "$conf")" = 600 ]
  grep -q '^Address = 10.66.66.3/32$' "$conf"
  grep -q '^Endpoint = 203.0.113.7:51820$' "$conf"
  grep -q '^PrivateKey = PRIV$' "$conf"
}

@test "add --qr prints a QR code" {
  configured
  run "$REPO_ROOT/wg-hub" add phone --qr
  [ "$status" -eq 0 ]
  [[ "$output" == *QRCODE* ]]
}

@test "add rejects a duplicate device" {
  configured
  "$REPO_ROOT/wg-hub" add phone
  run "$REPO_ROOT/wg-hub" add phone
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add rejects a bad name before touching the hub" {
  configured
  run "$REPO_ROOT/wg-hub" add 'bad/name'
  [ "$status" -eq 1 ]
  ! grep -q 'compute ssh' "$STUB_LOG"
}

@test "remove revokes on the hub and deletes local config" {
  configured
  "$REPO_ROOT/wg-hub" add phone
  run "$REPO_ROOT/wg-hub" remove phone
  [ "$status" -eq 0 ]
  grep -q "wg-hub-peer 'remove' 'phone'" "$STUB_LOG"
  [ ! -e "$WG_HUB_CONFIG_DIR/peers/phone.conf" ]
  ! grep -q '^phone ' "$WG_HUB_CONFIG_DIR/peers.db"
}

@test "remove refuses to remove this machine" {
  configured
  run "$REPO_ROOT/wg-hub" remove laptop
  [ "$status" -eq 1 ]
  [[ "$output" == *teardown* ]]
}

@test "isolate resolves names through the hub list" {
  configured
  run "$REPO_ROOT/wg-hub" isolate phone laptop
  [ "$status" -eq 0 ]
  grep -q "wg-hub-peer 'isolate' '10.66.66.3' '10.66.66.2'" "$STUB_LOG"
}

@test "list prints devices" {
  configured
  run "$REPO_ROOT/wg-hub" list
  [ "$status" -eq 0 ]
  [[ "$output" == *phone*10.66.66.3*never* ]]
}

@test "teardown aborts on wrong typed project id" {
  configured
  run "$REPO_ROOT/wg-hub" teardown <<<"nope"
  [ "$status" -eq 1 ]
  ! grep -q 'projects delete' "$STUB_LOG"
  [ -f "$WG_HUB_CONFIG_DIR/state" ]
}

@test "teardown deletes project, tunnel config and state on correct id" {
  configured
  stub uname 'echo Linux'
  stub systemctl ''
  mkdir -p "$WG_HUB_WG_DIR" && echo x >"$WG_HUB_WG_DIR/wg0.conf"
  run "$REPO_ROOT/wg-hub" teardown <<<"wg-hub-abc123"
  [ "$status" -eq 0 ]
  grep -q 'gcloud projects delete wg-hub-abc123 --quiet' "$STUB_LOG"
  [ ! -e "$WG_HUB_WG_DIR/wg0.conf" ]
  [ ! -e "$WG_HUB_CONFIG_DIR" ]
}

@test "setup refuses to overwrite an existing tunnel without --force" {
  export WG_HUB_WG_DIR="$BATS_TEST_TMPDIR/etc-wireguard"
  mkdir -p "$WG_HUB_WG_DIR" && echo x >"$WG_HUB_WG_DIR/wg0.conf"
  stub sudo '"$@"'
  stub uname 'echo Linux'
  run "$REPO_ROOT/wg-hub" setup
  [ "$status" -eq 1 ]
  [[ "$output" == *--force* ]]
}
