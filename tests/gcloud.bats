#!/usr/bin/env bats

load helpers

setup() {
  common_setup
  load_lib ui state gcloud hub
  export ACCOUNTS_FILE="$BATS_TEST_TMPDIR/accounts"
  export BILLING_ENABLED=False
  : >"$ACCOUNTS_FILE"
  stub gcloud '
case "$1 $2 $3" in
  "billing projects describe") echo "$BILLING_ENABLED" ;;
  "billing accounts list") cat "$ACCOUNTS_FILE" ;;
  "compute zones list") printf "us-west1-b\nus-west1-a\n" ;;
esac'
  find_gcloud
}

@test "find_gcloud uses gcloud from PATH" {
  [ "$GCLOUD" = "$STUB_BIN/gcloud" ]
}

@test "gen_project_id format" {
  [[ "$(gen_project_id)" =~ ^wg-hub-[a-z0-9]{6}$ ]]
}

@test "ensure_billing links the only open account" {
  printf '0000AA-BBBB11-CCCC22\tMy Billing\n' >"$ACCOUNTS_FILE"
  run ensure_billing wg-hub-abc123
  [ "$status" -eq 0 ]
  grep -q 'gcloud billing projects link wg-hub-abc123 --billing-account=0000AA-BBBB11-CCCC22' "$STUB_LOG"
}

@test "ensure_billing with no accounts explains how to add one" {
  run ensure_billing wg-hub-abc123
  [ "$status" -eq 1 ]
  [[ "$output" == *"billing account"* ]]
  ! grep -q 'projects link' "$STUB_LOG"
}

@test "ensure_billing prompts when several accounts exist (auto-yes picks first)" {
  printf 'ACC-1\tFirst\nACC-2\tSecond\n' >"$ACCOUNTS_FILE"
  WG_HUB_YES=1 run ensure_billing wg-hub-abc123
  [ "$status" -eq 0 ]
  grep -q 'billing-account=ACC-1' "$STUB_LOG"
}

@test "ensure_billing is a no-op when billing already enabled" {
  BILLING_ENABLED=True run ensure_billing wg-hub-abc123
  [ "$status" -eq 0 ]
  ! grep -q 'projects link' "$STUB_LOG"
}

@test "pick_zone returns the first zone in the region" {
  [ "$(pick_zone us-west1 wg-hub-abc123)" = us-west1-b ]
}

@test "hub_exec passes project, zone and command" {
  state_set PROJECT_ID wg-hub-abc123
  state_set ZONE us-west1-b
  hub_exec 'sudo true'
  grep -q 'gcloud compute ssh wg-hub --project=wg-hub-abc123 --zone=us-west1-b --quiet --command=sudo true' "$STUB_LOG"
}
