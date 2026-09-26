#!/usr/bin/env bash
# bootstrap.sh — one-time, idempotent hub setup. Runs as root on Ubuntu 24.04.
# Expects /tmp/wg-hub-peer to have been copied alongside it.
# Prints HUB_PUBKEY=<key> on stdout; everything else goes to stderr.
set -euo pipefail

WG_DIR=/etc/wireguard
PORT=51820

export DEBIAN_FRONTEND=noninteractive
if ! command -v wg >/dev/null || ! command -v iptables >/dev/null; then
  apt-get update -qq >&2
  apt-get install -y -qq wireguard iptables >&2
fi

install -m 755 /tmp/wg-hub-peer /usr/local/sbin/wg-hub-peer

umask 077
mkdir -p "$WG_DIR"
[ -f "$WG_DIR/hub.key" ] || wg genkey >"$WG_DIR/hub.key"
touch "$WG_DIR/isolate.rules"

if [ ! -f "$WG_DIR/wg0.conf" ]; then
  cat >"$WG_DIR/wg0.conf" <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = $PORT
PrivateKey = $(cat "$WG_DIR/hub.key")
PostUp = /usr/local/sbin/wg-hub-peer apply-isolation up
PostDown = /usr/local/sbin/wg-hub-peer apply-isolation down
EOF
fi

echo 'net.ipv4.ip_forward = 1' >/etc/sysctl.d/99-wg-hub.conf
sysctl -q -p /etc/sysctl.d/99-wg-hub.conf >&2

systemctl enable -q wg-quick@wg0 >&2
systemctl is-active -q wg-quick@wg0 || systemctl start wg-quick@wg0 >&2

echo "HUB_PUBKEY=$(wg pubkey <"$WG_DIR/hub.key")"
