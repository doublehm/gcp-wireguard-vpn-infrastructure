#!/usr/bin/env bash
# install.sh — install wg-hub and start setup.
#   curl -fsSL https://raw.githubusercontent.com/doublehm/gcp-wireguard-vpn-infrastructure/main/install.sh | bash
# Env: WG_HUB_REPO=owner/repo  WG_HUB_REF=branch  WG_HUB_NO_SETUP=1 (install only)
set -euo pipefail

REPO="${WG_HUB_REPO:-doublehm/gcp-wireguard-vpn-infrastructure}"
REF="${WG_HUB_REF:-main}"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/wg-hub"
BIN_DIR="$HOME/.local/bin"

say() { printf '==> %s\n' "$*" >&2; }
fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null || fail "curl is required."
command -v tar >/dev/null || fail "tar is required."
case "$(uname -s)" in Linux | Darwin) ;; *) fail "wg-hub supports Linux and macOS only." ;; esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading wg-hub ($REPO@$REF)..."
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar -xz -C "$tmp"
src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[ -x "$src/wg-hub" ] || fail "Download did not contain wg-hub."

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")" "$BIN_DIR"
mv "$src" "$DEST"
ln -sf "$DEST/wg-hub" "$BIN_DIR/wg-hub"
say "Installed: $BIN_DIR/wg-hub"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Add $BIN_DIR to your PATH to run \`wg-hub\` from anywhere." ;;
esac

if [ "${WG_HUB_NO_SETUP:-}" = 1 ]; then
  say "Run \`wg-hub setup\` when you're ready."
  exit 0
fi
exec "$BIN_DIR/wg-hub" setup
