#!/usr/bin/env bats

load helpers

setup() { common_setup; }

@test "step stops at the first failing command inside a stage and explains how to resume" {
  run bash -c "set -euo pipefail
    source '$REPO_ROOT/lib/ui.sh'
    stage() { false; echo SHOULD-NOT-PRINT; }
    step 'Doing a thing' 'Try turning it off and on.' stage"
  [ "$status" -ne 0 ]
  [[ "$output" != *SHOULD-NOT-PRINT* ]]
  [[ "$output" == *"Doing a thing failed"* ]]
  [[ "$output" == *"Try turning it off and on."* ]]
  [[ "$output" == *"wg-hub setup"* ]]
}

@test "step is silent about failure when the stage succeeds" {
  run bash -c "set -euo pipefail
    source '$REPO_ROOT/lib/ui.sh'
    step 'Fine' '' true"
  [ "$status" -eq 0 ]
  [[ "$output" != *failed* ]]
}

@test "confirm reads the answer and defaults to yes" {
  load_lib ui
  confirm "Go" <<<""
  ! confirm "Go" <<<"n"
  WG_HUB_YES=1 confirm "Go" <<<"n"
}

@test "prompt returns default on empty input" {
  load_lib ui
  [ "$(prompt Region us-west1 <<<"")" = us-west1 ]
  [ "$(prompt Region us-west1 <<<"us-east1")" = us-east1 ]
}
