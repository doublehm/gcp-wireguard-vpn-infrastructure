#!/usr/bin/env bats

load helpers

KEY_A="IUFP3Dj85MX1H0/cfioo1PWyDc3hnUGnBGsA+fX00kQ="
KEY_B="uWtBzxSj4z0WeD2yaMUuy4/KcTgL505TTQ+9V/tASmU="

setup() {
  common_setup
  export WG_DIR="$BATS_TEST_TMPDIR/wg"
  mkdir -p "$WG_DIR"
  cat >"$WG_DIR/wg0.conf" <<'EOF'
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = hubkey
EOF
  stub wg 'if [ "$1 $2 $3" = "show wg0 latest-handshakes" ]; then printf "%s\t1700000000\n" IUFP3Dj85MX1H0/cfioo1PWyDc3hnUGnBGsA+fX00kQ=; fi'
  # iptables -C (check) fails so inserts happen.
  stub iptables 'case "$1" in -C) exit 1 ;; esac'
  PEER="$REPO_ROOT/hub/wg-hub-peer"
}

@test "add appends a peer block and applies it live" {
  run "$PEER" add phone "$KEY_A" 10.66.66.3
  [ "$status" -eq 0 ]
  grep -q '^# wg-hub: phone$' "$WG_DIR/wg0.conf"
  grep -q "^PublicKey = $KEY_A$" "$WG_DIR/wg0.conf"
  grep -q '^AllowedIPs = 10.66.66.3/32$' "$WG_DIR/wg0.conf"
  grep -q "wg set wg0 peer $KEY_A allowed-ips 10.66.66.3/32" "$STUB_LOG"
}

@test "add rejects a duplicate name" {
  "$PEER" add phone "$KEY_A" 10.66.66.3
  run "$PEER" add phone "$KEY_B" 10.66.66.4
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "add rejects a duplicate IP" {
  "$PEER" add phone "$KEY_A" 10.66.66.3
  run "$PEER" add mac "$KEY_B" 10.66.66.3
  [ "$status" -eq 1 ]
  [[ "$output" == *"in use"* ]]
}

@test "add rejects bad input" {
  run "$PEER" add 'bad name' "$KEY_A" 10.66.66.3
  [ "$status" -eq 1 ]
  run "$PEER" add phone 'not-a-key' 10.66.66.3
  [ "$status" -eq 1 ]
  run "$PEER" add phone "$KEY_A" 10.0.0.3
  [ "$status" -eq 1 ]
}

@test "remove deletes only that block and removes it live" {
  "$PEER" add phone "$KEY_A" 10.66.66.3
  "$PEER" add mac "$KEY_B" 10.66.66.4
  run "$PEER" remove phone
  [ "$status" -eq 0 ]
  ! grep -q 'wg-hub: phone' "$WG_DIR/wg0.conf"
  ! grep -q "$KEY_A" "$WG_DIR/wg0.conf"
  grep -q 'wg-hub: mac' "$WG_DIR/wg0.conf"
  grep -q "$KEY_B" "$WG_DIR/wg0.conf"
  grep -q '^\[Interface\]' "$WG_DIR/wg0.conf"
  grep -q "wg set wg0 peer $KEY_A remove" "$STUB_LOG"
}

@test "remove unknown peer fails" {
  run "$PEER" remove ghost
  [ "$status" -eq 1 ]
  [[ "$output" == *"No peer"* ]]
}

@test "used-ips lists peer IPs" {
  "$PEER" add phone "$KEY_A" 10.66.66.3
  "$PEER" add mac "$KEY_B" 10.66.66.4
  run "$PEER" used-ips
  [ "$output" = $'10.66.66.3\n10.66.66.4' ]
}

@test "list shows name, ip and handshake" {
  "$PEER" add phone "$KEY_A" 10.66.66.3
  "$PEER" add mac "$KEY_B" 10.66.66.4
  run "$PEER" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "phone 10.66.66.3 1700000000" ]
  [ "${lines[1]}" = "mac 10.66.66.4 0" ]
}

@test "isolate records the rule once and inserts both directions" {
  run "$PEER" isolate 10.66.66.3 10.66.66.4
  [ "$status" -eq 0 ]
  "$PEER" isolate 10.66.66.3 10.66.66.4
  [ "$(wc -l <"$WG_DIR/isolate.rules" | tr -d ' ')" -eq 1 ]
  grep -q 'iptables -I FORWARD -i wg0 -s 10.66.66.3 -d 10.66.66.4 -j REJECT' "$STUB_LOG"
  grep -q 'iptables -I FORWARD -i wg0 -s 10.66.66.4 -d 10.66.66.3 -j REJECT' "$STUB_LOG"
}

@test "apply-isolation down deletes the rules" {
  echo "10.66.66.3 10.66.66.4" >"$WG_DIR/isolate.rules"
  run "$PEER" apply-isolation down
  [ "$status" -eq 0 ]
  grep -q 'iptables -D FORWARD -i wg0 -s 10.66.66.3 -d 10.66.66.4 -j REJECT' "$STUB_LOG"
  grep -q 'iptables -D FORWARD -i wg0 -s 10.66.66.4 -d 10.66.66.3 -j REJECT' "$STUB_LOG"
}

@test "unknown subcommand fails" {
  run "$PEER" frob
  [ "$status" -eq 1 ]
}
