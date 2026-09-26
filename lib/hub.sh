# shellcheck shell=bash
# hub.sh — create the hub VM and talk to it over SSH.

VM_NAME="wg-hub"
IP_NAME="wg-hub-ip"
FW_NAME="wg-hub-allow-wireguard"
NET_TIER="STANDARD"

_project() { state_get PROJECT_ID; }
_zone() { state_get ZONE; }
_region() { state_get REGION; }

pick_zone() {
  "$GCLOUD" compute zones list --project="$2" --filter="region:$1" \
    --format='value(name)' --sort-by=name | head -n1
}

# ensure_static_ip — print the hub's static external IP, reserving it if needed.
ensure_static_ip() {
  local p r ip
  p="$(_project)"
  r="$(_region)"
  ip="$("$GCLOUD" compute addresses describe "$IP_NAME" --project="$p" --region="$r" \
    --format='value(address)' 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    "$GCLOUD" compute addresses create "$IP_NAME" --project="$p" --region="$r" \
      --network-tier="$NET_TIER" >&2 || return 1
    ip="$("$GCLOUD" compute addresses describe "$IP_NAME" --project="$p" --region="$r" \
      --format='value(address)')"
  fi
  echo "$ip"
}

ensure_firewall() {
  local p
  p="$(_project)"
  if "$GCLOUD" compute firewall-rules describe "$FW_NAME" --project="$p" >/dev/null 2>&1; then
    return 0
  fi
  "$GCLOUD" compute firewall-rules create "$FW_NAME" --project="$p" --network=default \
    --allow=udp:51820 --target-tags=wg-hub --source-ranges=0.0.0.0/0 \
    --description="WireGuard for wg-hub" >&2
}

ensure_vm() {
  local p z
  p="$(_project)"
  z="$(_zone)"
  if "$GCLOUD" compute instances describe "$VM_NAME" --project="$p" --zone="$z" >/dev/null 2>&1; then
    return 0
  fi
  "$GCLOUD" compute instances create "$VM_NAME" --project="$p" --zone="$z" \
    --machine-type=e2-micro \
    --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --can-ip-forward --tags=wg-hub \
    --network-tier="$NET_TIER" --address="$1" >&2
}

hub_exec() {
  "$GCLOUD" compute ssh "$VM_NAME" --project="$(_project)" --zone="$(_zone)" --quiet --command="$1"
}

wait_ssh() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if hub_exec true >/dev/null 2>&1; then return 0; fi
    info "Waiting for the hub to accept SSH (attempt $i/10)..."
    sleep $((i * 5))
  done
  return 1
}

# bootstrap_hub — copy hub scripts, run setup, print the hub public key.
bootstrap_hub() {
  local key
  "$GCLOUD" compute scp --project="$(_project)" --zone="$(_zone)" --quiet \
    "$WG_HUB_ROOT/hub/bootstrap.sh" "$WG_HUB_ROOT/hub/wg-hub-peer" "$VM_NAME:/tmp/" >&2 || return 1
  key="$(hub_exec 'sudo bash /tmp/bootstrap.sh' | sed -n 's/^HUB_PUBKEY=//p' | tr -d '\r')"
  [ -n "$key" ] || return 1
  echo "$key"
}

hub_peer() {
  local args='' a
  for a in "$@"; do args="$args '$a'"; done
  hub_exec "sudo /usr/local/sbin/wg-hub-peer$args"
}
