# shellcheck shell=bash
# commands.sh — wg-hub subcommands.

# ---------- setup ----------

cmd_setup() {
  local force=0 arg
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      -y | --yes) export WG_HUB_YES=1 ;;
      *) die "Unknown option for setup: $arg" ;;
    esac
  done

  heading "wg-hub setup"
  if [ -z "$(state_get LOCAL_PEER)" ] && tunnel_exists; then
    [ "$force" -eq 1 ] || die "A WireGuard config '$(wg_conf_dir)/wg0.conf' already exists on this machine.
  Re-run with --force to replace it (the old tunnel will be stopped)."
  fi

  step "Installing WireGuard tools" "Check the package manager output above." ensure_packages
  step "Checking the Google Cloud CLI" "Manual install: https://cloud.google.com/sdk/docs/install" ensure_gcloud
  step "Signing in to Google Cloud" "Try \`$GCLOUD auth login\` manually." ensure_auth

  [ -n "$(state_get PROJECT_ID)" ] || _setup_plan

  local project
  project="$(state_get PROJECT_ID)"
  step "Creating project $project" \
    "New Google Cloud accounts must accept the terms first: https://console.cloud.google.com" \
    ensure_project "$project"
  step "Linking billing" "Check https://console.cloud.google.com/billing" ensure_billing "$project"
  step "Enabling the Compute Engine API (can take a minute)" "" ensure_compute "$project"
  step "Choosing a zone" "" _setup_zone
  step "Reserving a static IP" "" _setup_ip
  step "Opening UDP port 51820" "" ensure_firewall
  step "Creating the hub VM (e2-micro)" "" ensure_vm "$(state_get HUB_IP)"
  step "Waiting for the hub to boot" "The VM may still be starting; wait a minute." wait_ssh
  step "Configuring WireGuard on the hub" "" _setup_bootstrap
  step "Connecting this machine" "" _setup_local "$force"
  step "Verifying the tunnel" "Check \`wg-hub status\`." _setup_verify

  heading "Done! This machine is $(state_get LOCAL_IP) on your VPN."
  cat >&2 <<EOF
Next steps:
  wg-hub add phone --qr    add your phone (scan with the WireGuard app)
  wg-hub add work-laptop   add another computer (copy the printed config to it)
  wg-hub list              see connected devices
EOF
}

_setup_plan() {
  local project region
  project="$(gen_project_id)"
  region="$(suggest_region)"
  heading "Here's the plan"
  cat >&2 <<EOF
  • New Google Cloud project:  $project
  • Hub VM:                    e2-micro, Ubuntu 24.04, static IP
  • Firewall:                  UDP 51820 open to the hub only
  • Cost:                      e2-micro is in Google's free tier in us-west1,
                               us-central1 and us-east1; a static IP may cost
                               a few dollars a month. See the README.
EOF
  region="$(prompt "Region" "$region")"
  if ! is_free_region "$region"; then
    warn "$region is outside the free tier; the VM costs about \$7/month."
  fi
  confirm "Create these resources in your Google Cloud account?" || die "Aborted. Nothing was created."
  state_set PROJECT_ID "$project"
  state_set REGION "$region"
}

_setup_zone() {
  [ -n "$(state_get ZONE)" ] && return 0
  local zone
  zone="$(pick_zone "$(state_get REGION)" "$(state_get PROJECT_ID)")"
  [ -n "$zone" ] || die "No zones found for region $(state_get REGION)."
  state_set ZONE "$zone"
}

_setup_ip() {
  local ip
  ip="$(ensure_static_ip)"
  [ -n "$ip" ] || return 1
  state_set HUB_IP "$ip"
}

_setup_bootstrap() {
  local key
  key="$(bootstrap_hub)"
  state_set HUB_PUBKEY "$key"
}

_local_name() {
  local n
  n="$(hostname 2>/dev/null || uname -n)"
  n="${n%%.*}"
  n="$(printf '%s' "$n" | tr -c 'A-Za-z0-9_-' '-' | cut -c1-32)"
  echo "${n:-this-machine}"
}

_setup_local() {
  local force="$1" name keys priv pub ip
  if [ -n "$(state_get LOCAL_PEER)" ] && tunnel_exists; then
    ok "This machine is already connected"
    return 0
  fi
  name="$(state_get LOCAL_PEER)"
  [ -n "$name" ] || name="$(_local_name)"
  keys="$(keygen)"
  priv="${keys%% *}"
  pub="${keys##* }"
  # Re-running after a partial failure: drop any stale registration first.
  hub_peer remove "$name" >/dev/null 2>&1 || true
  ip="$(hub_peer used-ips | tr -d '\r' | next_free_ip)"
  hub_peer add "$name" "$pub" "$ip" >/dev/null
  if [ "$force" -eq 1 ]; then tunnel_down; fi
  is_macos || info "Writing $(wg_conf_dir)/wg0.conf needs administrator rights (sudo)."
  render_client_conf "$priv" "$ip" "$(state_get HUB_PUBKEY)" "$(state_get HUB_IP)" | tunnel_write_conf
  tunnel_up
  peers_db_remove "$name"
  peers_db_add "$name" "$ip" "$pub"
  state_set LOCAL_PEER "$name"
  state_set LOCAL_IP "$ip"
}

_setup_verify() {
  local i
  for i in 1 2 3 4 5; do
    if ping -c 1 "$HUB_VPN_IP" >/dev/null 2>&1; then
      ok "Hub reachable at $HUB_VPN_IP"
      return 0
    fi
    sleep "$i"
  done
  return 1
}

# ---------- device management ----------

_require_hub() {
  require_state
  find_gcloud || die "Google Cloud CLI not found. Run \`wg-hub setup\`."
}

cmd_add() {
  local name='' qr=0 arg
  for arg in "$@"; do
    case "$arg" in
      --qr) qr=1 ;;
      -*) die "Unknown option for add: $arg" ;;
      *)
        [ -z "$name" ] || die "Usage: wg-hub add <name> [--qr]"
        name="$arg"
        ;;
    esac
  done
  [ -n "$name" ] || die "Usage: wg-hub add <name> [--qr]"
  validate_name "$name"
  _require_hub
  [ -z "$(peers_db_ip "$name")" ] || die "Device '$name' already exists. Remove it first with \`wg-hub remove $name\`."

  local keys priv pub ip conf
  keys="$(keygen)"
  priv="${keys%% *}"
  pub="${keys##* }"
  ip="$({
    hub_peer used-ips | tr -d '\r'
    peers_db_ips
  } | next_free_ip)"
  info "Registering $name ($ip) on the hub..."
  hub_peer add "$name" "$pub" "$ip" >/dev/null
  peers_db_add "$name" "$ip" "$pub"

  conf="$(peer_conf_path "$name")"
  mkdir -p "$(dirname "$conf")"
  chmod 700 "$(dirname "$conf")"
  (
    umask 077
    render_client_conf "$priv" "$ip" "$(state_get HUB_PUBKEY)" "$(state_get HUB_IP)" >"$conf"
  )
  ok "Added $name at $ip"
  if [ "$qr" -eq 1 ]; then
    qrencode -t ansiutf8 <"$conf"
    info "Scan this with the WireGuard app (Add tunnel → Scan from QR code)."
  else
    info "Config saved to $conf"
    info "For a phone: qrencode -t ansiutf8 < $conf   (or re-add with --qr)"
    info "For a computer: copy it to /etc/wireguard/wg0.conf there and run wg-quick up wg0."
  fi
}

_ago() {
  local t="$1" now d
  if [ "$t" = 0 ]; then
    echo never
    return
  fi
  now="$(date +%s)"
  d=$((now - t))
  if [ "$d" -lt 120 ]; then
    echo "${d}s ago"
  elif [ "$d" -lt 7200 ]; then
    echo "$((d / 60))m ago"
  elif [ "$d" -lt 172800 ]; then
    echo "$((d / 3600))h ago"
  else
    echo "$((d / 86400))d ago"
  fi
}

cmd_list() {
  _require_hub
  local name ip t
  printf '%-20s %-14s %s\n' DEVICE IP "LAST HANDSHAKE"
  hub_peer list | tr -d '\r' | while read -r name ip t; do
    [ -n "$name" ] || continue
    printf '%-20s %-14s %s\n' "$name" "$ip" "$(_ago "${t:-0}")"
  done
}

cmd_remove() {
  [ $# -eq 1 ] || die "Usage: wg-hub remove <name>"
  local name="$1"
  validate_name "$name"
  _require_hub
  [ "$name" != "$(state_get LOCAL_PEER)" ] ||
    die "'$name' is this machine. Use \`wg-hub teardown\` to remove everything."
  hub_peer remove "$name" >/dev/null
  peers_db_remove "$name"
  rm -f "$(peer_conf_path "$name")"
  ok "Removed $name"
}

cmd_isolate() {
  [ $# -eq 2 ] || die "Usage: wg-hub isolate <device-a> <device-b>"
  _require_hub
  local list a b
  list="$(hub_peer list | tr -d '\r')"
  a="$(printf '%s\n' "$list" | resolve_peer "$1")"
  b="$(printf '%s\n' "$list" | resolve_peer "$2")"
  hub_peer isolate "$a" "$b" >/dev/null
  ok "$1 ($a) and $2 ($b) can no longer reach each other"
}

# ---------- status / teardown ----------

cmd_status() {
  _require_hub
  local vm
  heading "Hub"
  printf '  Project: %s\n  Zone:    %s\n  Address: %s\n' \
    "$(state_get PROJECT_ID)" "$(state_get ZONE)" "$(state_get HUB_IP)"
  vm="$("$GCLOUD" compute instances describe "$VM_NAME" --project="$(state_get PROJECT_ID)" \
    --zone="$(state_get ZONE)" --format='value(status)' 2>/dev/null || echo UNKNOWN)"
  printf '  VM:      %s\n' "$vm"
  heading "This machine"
  printf '  Device:  %s (%s)\n' "$(state_get LOCAL_PEER)" "$(state_get LOCAL_IP)"
  if ping -c 1 "$HUB_VPN_IP" >/dev/null 2>&1; then
    ok "Tunnel up: hub reachable at $HUB_VPN_IP"
  else
    warn "Hub not reachable at $HUB_VPN_IP. Check \`sudo wg show\`."
  fi
}

cmd_teardown() {
  require_state
  local project ans
  project="$(state_get PROJECT_ID)"
  heading "Teardown"
  cat >&2 <<EOF
This permanently deletes:
  • Google Cloud project $project (hub VM, IP, firewall — all devices lose access)
  • This machine's tunnel config ($(wg_conf_dir)/wg0.conf)
  • Saved device configs in $(state_dir)
EOF
  printf 'Type the project ID to confirm: ' >&2
  _read_tty ans
  [ "$ans" = "$project" ] || die "Aborted. Nothing was deleted."

  if [ -n "$(state_get LOCAL_PEER)" ]; then
    info "Stopping the local tunnel..."
    tunnel_down
    $(sudo_cmd) rm -f "$(wg_conf_dir)/wg0.conf"
  fi
  find_gcloud || die "Google Cloud CLI not found; delete project $project in the console."
  info "Deleting project $project..."
  "$GCLOUD" projects delete "$project" --quiet
  rm -rf "$(state_dir)"
  ok "Everything removed. Google keeps deleted projects recoverable for 30 days."
}
