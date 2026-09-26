#!/usr/bin/env bats

load helpers

setup() {
  common_setup
  load_lib ui state
}

@test "state_set then state_get round-trips" {
  state_set PROJECT_ID wg-hub-abc123
  [ "$(state_get PROJECT_ID)" = "wg-hub-abc123" ]
}

@test "state_set overwrites an existing key" {
  state_set ZONE us-west1-b
  state_set ZONE us-east1-b
  [ "$(state_get ZONE)" = "us-east1-b" ]
  [ "$(grep -c '^ZONE=' "$WG_HUB_CONFIG_DIR/state")" -eq 1 ]
}

@test "state_get of missing key is empty and succeeds" {
  run state_get NOPE
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "values with = and / survive" {
  state_set HUB_PUBKEY 'ab+c/d=='
  [ "$(state_get HUB_PUBKEY)" = 'ab+c/d==' ]
}

@test "state dir is 700 and state file is 600" {
  state_set A b
  [ "$(file_mode "$WG_HUB_CONFIG_DIR")" = "700" ]
  [ "$(file_mode "$WG_HUB_CONFIG_DIR/state")" = "600" ]
}

@test "require_state fails before setup" {
  run require_state
  [ "$status" -eq 1 ]
  [[ "$output" == *"wg-hub setup"* ]]
}
