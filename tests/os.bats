#!/usr/bin/env bats

load helpers

setup() {
  common_setup
  load_lib ui os
  stub uname 'echo Linux'
}

pm_for() {
  WG_HUB_OS_RELEASE="$REPO_ROOT/tests/fixtures/os-release/$1" detect_pm
}

@test "detect_pm: fedora -> dnf" { [ "$(pm_for fedora)" = dnf ]; }
@test "detect_pm: ubuntu -> apt" { [ "$(pm_for ubuntu)" = apt ]; }
@test "detect_pm: debian -> apt" { [ "$(pm_for debian)" = apt ]; }
@test "detect_pm: arch -> pacman" { [ "$(pm_for arch)" = pacman ]; }
@test "detect_pm: opensuse -> zypper" { [ "$(pm_for opensuse)" = zypper ]; }
@test "detect_pm: linuxmint via ID_LIKE -> apt" { [ "$(pm_for linuxmint)" = apt ]; }

@test "detect_pm: unsupported distro fails" {
  run pm_for unsupported
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported"* ]]
}

@test "detect_pm: macOS -> brew" {
  stub uname 'echo Darwin'
  [ "$(detect_pm)" = brew ]
}

@test "pkg_install_cmd apt updates first and installs both packages" {
  run pkg_install_cmd apt
  [[ "$output" == *"apt-get update"* ]]
  [[ "$output" == *"wireguard-tools qrencode"* ]]
}

@test "pkg_install_cmd brew never uses sudo" {
  run pkg_install_cmd brew
  [[ "$output" != *sudo* ]]
  [[ "$output" == "brew install wireguard-tools qrencode" ]]
}

@test "pkg_install_cmd dnf" {
  run pkg_install_cmd dnf
  [[ "$output" == *"dnf install -y wireguard-tools qrencode" ]]
}

@test "suggest_region by timezone" {
  [ "$(WG_HUB_TZ=America/Los_Angeles suggest_region)" = us-west1 ]
  [ "$(WG_HUB_TZ=Asia/Tokyo suggest_region)" = us-west1 ]
  [ "$(WG_HUB_TZ=America/Chicago suggest_region)" = us-central1 ]
  [ "$(WG_HUB_TZ=Europe/Berlin suggest_region)" = us-east1 ]
  [ "$(WG_HUB_TZ=America/New_York suggest_region)" = us-east1 ]
}

@test "is_free_region" {
  is_free_region us-west1
  is_free_region us-central1
  is_free_region us-east1
  ! is_free_region europe-west3
}
