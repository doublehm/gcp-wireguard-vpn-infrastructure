# shellcheck shell=bash
# peers.sh — client-side device bookkeeping, keys, and config rendering.

SUBNET_PREFIX="10.66.66."
# shellcheck disable=SC2034 # used by commands.sh
HUB_VPN_IP="10.66.66.1"
WG_PORT=51820

validate_name() {
  case "$1" in
    '' | *[!A-Za-z0-9_-]*) die "Invalid device name '$1'. Use letters, digits, - or _." ;;
  esac
  [ "${#1}" -le 32 ] || die "Device name too long (max 32): $1"
}

# next_free_ip — read used IPs on stdin, print the first free one.
next_free_ip() {
  local used n
  used=" $(tr '\n' ' ') "
  n=2
  while [ "$n" -le 254 ]; do
    case "$used" in
      *" $SUBNET_PREFIX$n "*) ;;
      *)
        echo "$SUBNET_PREFIX$n"
        return 0
        ;;
    esac
    n=$((n + 1))
  done
  die "Subnet full: no free addresses left in ${SUBNET_PREFIX}0/24."
}

# keygen — print "PRIVATE PUBLIC".
keygen() {
  local priv pub
  priv="$(wg genkey)"
  pub="$(printf '%s\n' "$priv" | wg pubkey)"
  echo "$priv $pub"
}

render_client_conf() {
  cat <<EOF
[Interface]
PrivateKey = $1
Address = $2/32

[Peer]
PublicKey = $3
Endpoint = $4:$WG_PORT
AllowedIPs = ${SUBNET_PREFIX}0/24
PersistentKeepalive = 25
EOF
}

peers_db() { echo "$(state_dir)/peers.db"; }

peers_db_add() {
  state_init
  (
    umask 077
    echo "$1 $2 $3" >>"$(peers_db)"
  )
  chmod 600 "$(peers_db)"
}

peers_db_remove() {
  local f tmp
  f="$(peers_db)"
  [ -f "$f" ] || return 0
  tmp="$f.tmp.$$"
  (
    umask 077
    awk -v n="$1" '$1 != n' "$f" >"$tmp"
  )
  mv "$tmp" "$f"
}

peers_db_ip() {
  local f
  f="$(peers_db)"
  [ -f "$f" ] || return 0
  awk -v n="$1" '$1 == n { print $2 }' "$f"
}

peers_db_ips() {
  local f
  f="$(peers_db)"
  [ -f "$f" ] || return 0
  awk '{ print $2 }' "$f"
}

# resolve_peer NAME_OR_IP — print the VPN IP. Reads "name ip ..." lines
# (the hub's peer list) on stdin to resolve names.
resolve_peer() {
  case "$1" in
    "$SUBNET_PREFIX"*)
      cat >/dev/null
      echo "$1"
      return
      ;;
  esac
  local ip
  ip="$(awk -v n="$1" '$1 == n { print $2 }')"
  [ -n "$ip" ] || die "Unknown device '$1'. See \`wg-hub list\`."
  echo "$ip"
}

peer_conf_path() { echo "$(state_dir)/peers/$1.conf"; }
