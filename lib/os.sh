# shellcheck shell=bash
# os.sh — OS detection, package install, and local tunnel service management.

PACKAGES="wireguard-tools qrencode"
LAUNCHD_LABEL="com.wg-hub.wg0"
LAUNCHD_PLIST="/Library/LaunchDaemons/$LAUNCHD_LABEL.plist"

is_macos() { [ "$(uname -s)" = Darwin ]; }

# detect_pm — print the package manager for this machine.
detect_pm() {
  if is_macos; then
    echo brew
    return
  fi
  local f="${WG_HUB_OS_RELEASE:-/etc/os-release}" id='' like='' word
  [ -r "$f" ] || die "Cannot read $f to detect your Linux distribution."
  id="$(sed -n 's/^ID=//p' "$f" | tr -d '"')"
  like="$(sed -n 's/^ID_LIKE=//p' "$f" | tr -d '"')"
  for word in $id $like; do
    case "$word" in
      fedora | rhel | centos | rocky | almalinux | amzn) echo dnf && return ;;
      debian | ubuntu | linuxmint | pop | raspbian) echo apt && return ;;
      arch | manjaro | endeavouros) echo pacman && return ;;
      opensuse* | suse | sles) echo zypper && return ;;
    esac
  done
  die "Unsupported OS '$id'. Supported: Fedora/RHEL, Debian/Ubuntu, Arch, openSUSE, macOS."
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then echo ''; else echo sudo; fi
}

# pkg_install_cmd PM — print the command that installs our packages.
pkg_install_cmd() {
  local s
  s="$(sudo_cmd)"
  s="${s:+$s }"
  case "$1" in
    dnf) echo "${s}dnf install -y $PACKAGES" ;;
    apt) echo "${s}apt-get update && ${s}apt-get install -y $PACKAGES" ;;
    pacman) echo "${s}pacman -S --needed --noconfirm $PACKAGES" ;;
    zypper) echo "${s}zypper --non-interactive install $PACKAGES" ;;
    brew) echo "brew install $PACKAGES" ;;
    *) die "Unknown package manager: $1" ;;
  esac
}

ensure_packages() {
  if command -v wg >/dev/null 2>&1 && command -v qrencode >/dev/null 2>&1; then
    ok "WireGuard tools already installed"
    return 0
  fi
  local pm cmd
  pm="$(detect_pm)"
  if [ "$pm" = brew ] && ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is required on macOS. Install it from https://brew.sh and re-run."
  fi
  cmd="$(pkg_install_cmd "$pm")"
  [ "$pm" != brew ] && info "Installing packages needs administrator rights (sudo)."
  info "Running: $cmd"
  sh -c "$cmd"
}

wg_conf_dir() {
  if [ -n "${WG_HUB_WG_DIR:-}" ]; then
    echo "$WG_HUB_WG_DIR"
  elif is_macos; then
    echo "$(brew --prefix)/etc/wireguard"
  else
    echo /etc/wireguard
  fi
}

tunnel_exists() {
  local s
  s="$(sudo_cmd)"
  $s test -e "$(wg_conf_dir)/wg0.conf"
}

# tunnel_write_conf — write stdin to wg0.conf as root with mode 600.
tunnel_write_conf() {
  local s dir
  s="$(sudo_cmd)"
  dir="$(wg_conf_dir)"
  $s mkdir -p "$dir"
  $s sh -c "umask 077; cat > '$dir/wg0.conf'"
}

tunnel_up() {
  local s
  s="$(sudo_cmd)"
  if is_macos; then
    local prefix
    prefix="$(brew --prefix)"
    $s tee "$LAUNCHD_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$prefix/bin/wg-quick</string><string>up</string><string>wg0</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$prefix/bin:$prefix/sbin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>/var/log/wg-hub.log</string>
</dict>
</plist>
EOF
    $s launchctl bootout system "$LAUNCHD_PLIST" 2>/dev/null || true
    $s launchctl bootstrap system "$LAUNCHD_PLIST"
  else
    $s systemctl enable --now wg-quick@wg0
  fi
}

tunnel_down() {
  local s
  s="$(sudo_cmd)"
  if is_macos; then
    $s launchctl bootout system "$LAUNCHD_PLIST" 2>/dev/null || true
    $s rm -f "$LAUNCHD_PLIST"
    $s "$(brew --prefix)/bin/wg-quick" down wg0 2>/dev/null || true
  else
    $s systemctl disable --now wg-quick@wg0 2>/dev/null || true
  fi
}

local_timezone() {
  if [ -n "${WG_HUB_TZ:-}" ]; then echo "$WG_HUB_TZ" && return; fi
  if [ -n "${TZ:-}" ]; then echo "${TZ#:}" && return; fi
  local link
  link="$(readlink /etc/localtime 2>/dev/null || true)"
  echo "${link#*zoneinfo/}"
}

# suggest_region — nearest free-tier region, guessed from the timezone.
suggest_region() {
  case "$(local_timezone)" in
    America/Los_Angeles | America/Vancouver | America/Tijuana | America/Anchorage | \
      Asia/* | Australia/* | Pacific/*) echo us-west1 ;;
    America/Chicago | America/Denver | America/Phoenix | America/Edmonton | \
      America/Winnipeg | America/Mexico_City | America/Regina | America/Boise) echo us-central1 ;;
    *) echo us-east1 ;;
  esac
}

is_free_region() {
  case "$1" in us-west1 | us-central1 | us-east1) return 0 ;; *) return 1 ;; esac
}
