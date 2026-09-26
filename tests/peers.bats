#!/usr/bin/env bats

load helpers

setup() {
  common_setup
  load_lib ui state peers
}

@test "validate_name accepts good names" {
  validate_name phone
  validate_name my-mac_2
}

@test "validate_name rejects bad names" {
  run validate_name 'a b'
  [ "$status" -eq 1 ]
  run validate_name '../x'
  [ "$status" -eq 1 ]
  run validate_name "$(printf 'a%.0s' $(seq 33))"
  [ "$status" -eq 1 ]
  run validate_name ''
  [ "$status" -eq 1 ]
}

@test "next_free_ip starts at .2" {
  [ "$(printf '' | next_free_ip)" = 10.66.66.2 ]
}

@test "next_free_ip fills gaps" {
  [ "$(printf '10.66.66.2\n10.66.66.4\n' | next_free_ip)" = 10.66.66.3 ]
}

@test "next_free_ip fails when full" {
  run bash -c "source '$REPO_ROOT/lib/ui.sh'; source '$REPO_ROOT/lib/peers.sh'; seq 2 254 | sed 's/^/10.66.66./' | next_free_ip"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Subnet full"* ]]
}

@test "render_client_conf output" {
  run render_client_conf PRIV 10.66.66.3 HUBPUB 203.0.113.7
  [ "$output" = "[Interface]
PrivateKey = PRIV
Address = 10.66.66.3/32

[Peer]
PublicKey = HUBPUB
Endpoint = 203.0.113.7:51820
AllowedIPs = 10.66.66.0/24
PersistentKeepalive = 25" ]
}

@test "keygen prints a private and public key" {
  stub wg 'case "$1" in genkey) echo PRIVKEY ;; pubkey) read -r k; echo "PUB-$k" ;; esac'
  [ "$(keygen)" = "PRIVKEY PUB-PRIVKEY" ]
}

@test "peers db round trip" {
  peers_db_add phone 10.66.66.3 KEYP
  peers_db_add mac 10.66.66.4 KEYM
  [ "$(peers_db_ip phone)" = 10.66.66.3 ]
  [ "$(file_mode "$WG_HUB_CONFIG_DIR/peers.db")" = 600 ]
  peers_db_remove phone
  [ -z "$(peers_db_ip phone)" ]
  [ "$(peers_db_ip mac)" = 10.66.66.4 ]
}

@test "resolve_peer by name or IP" {
  list='phone 10.66.66.3 0
mac 10.66.66.4 1700000000'
  [ "$(echo "$list" | resolve_peer phone)" = 10.66.66.3 ]
  [ "$(echo "$list" | resolve_peer 10.66.66.9)" = 10.66.66.9 ]
  run resolve_peer ghost <<<"$list"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown device"* ]]
}
