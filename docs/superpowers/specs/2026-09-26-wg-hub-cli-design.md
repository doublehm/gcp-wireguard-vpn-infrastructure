# wg-hub CLI — Design

Date: 2026-09-26
Status: Approved (pending spec review)

## Goal

Turn this repo into a public, one-command terminal tool that lets anyone on
Linux or macOS stand up a private WireGuard hub on their own GCP account and
connect their devices to it for **remote access** (split tunnel: only the VPN
subnet is routed, not all internet traffic).

The repo must contain no personal data (project IDs, IPs, keys, home paths).

## Non-goals

- Windows clients (phones are supported only via QR code / config file).
- Multiple hubs / region switching.
- Full-tunnel (route-all-traffic) VPN mode.
- IPv6 inside the tunnel.
- Migrating the author's existing hub; it keeps working and is torn down
  manually.

## Decisions

| Topic | Decision |
|---|---|
| Client OS | Linux (dnf, apt, pacman, zypper) and macOS (Homebrew) |
| Language | Pure Bash, compatible with Bash 3.2 (stock macOS), shellcheck-clean |
| GCP project | Always create a dedicated new project `wg-hub-<random6>` per install |
| Hub setup | Own minimal bootstrap script; no third-party installer |
| Keys | Generated on the client; hub only ever receives public keys |
| Hubs | Exactly one per install; free-tier US region suggested by timezone |
| Subnet | `10.66.66.0/24`, hub `10.66.66.1`, first client `10.66.66.2` |
| Peer policy | All peers can reach each other by default; `isolate` blocks pairs |

## Command surface

```
wg-hub setup [--force]    # guided first-time install
wg-hub add <name> [--qr]  # add a device; --qr prints a QR code for mobile
wg-hub list               # peers with IP and last handshake
wg-hub remove <name>      # revoke a peer
wg-hub isolate <a> <b>    # block traffic between two peers (both directions)
wg-hub status             # local tunnel + hub health
wg-hub teardown           # delete GCP project and local tunnel (typed confirmation)
wg-hub help | --version
```

Install paths:
- `curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash`
  downloads to `~/.local/share/wg-hub` and symlinks `~/.local/bin/wg-hub`.
- Or run `./wg-hub` directly from a clone.

## `setup` flow

Every step checks state first and is skipped if already satisfied, so
re-running `setup` after a failure resumes.

1. **Detect OS** via `uname` and `/etc/os-release` (`ID`, `ID_LIKE`).
   Map to `dnf | apt | pacman | zypper | brew`. Install `wireguard-tools`
   and `qrencode`. macOS without Homebrew → clear error with install link.
   Unsupported distro → error listing supported ones.
2. **gcloud**: if not on `PATH` and not at `~/google-cloud-sdk/bin/gcloud`,
   install via Google's official installer non-interactively into
   `~/google-cloud-sdk`. If no active account, run `gcloud auth login`.
3. **Project**: generate `wg-hub-<random6>`, `gcloud projects create`.
   List open billing accounts; auto-select if exactly one, otherwise prompt.
   Link billing, enable `compute.googleapis.com`.
4. **Region**: suggest the nearest of `us-west1`, `us-central1`, `us-east1`
   (free-tier e2-micro regions) from the machine's timezone; allow any
   override. (Changed from measured latency: GCP front ends are anycast, so
   client-side pings don't reflect region distance.) Non-free
   region → cost warning (~$7/month) and confirm.
5. **Hub**: reserve a static external IP, create `e2-micro` Ubuntu 24.04 VM
   (`--can-ip-forward`, tag `wg-hub`), create firewall rule allowing UDP 51820
   to that tag. Wait for SSH with retry/backoff (not a fixed sleep). Send
   `hub/bootstrap.sh` over `gcloud compute ssh` and run it as root; capture the
   hub public key it prints.
6. **This machine**: generate a keypair locally, register it on the hub as
   peer `<hostname>` at `10.66.66.2`, write `/etc/wireguard/wg0.conf`, bring up
   the tunnel (systemd `wg-quick@wg0` on Linux; launchd daemon on macOS).
7. **Verify**: ping `10.66.66.1`; print next steps (`wg-hub add phone --qr`).

Before step 3 the tool shows a summary (project name, region, what will be
created, expected cost) and asks one Y/n confirmation.

If a local `wg0` interface or `/etc/wireguard/wg0.conf` already exists,
`setup` refuses unless `--force` is given.

## Code layout

```
wg-hub               entrypoint: arg parsing, sources lib/*, dispatches cmd_*
lib/ui.sh            colors (disabled when not a TTY), info/warn/die, confirm, prompt, step
lib/os.sh            detect_os, pkg_install, tunnel_up/tunnel_down (systemd|launchd)
lib/gcloud.sh        ensure_gcloud, ensure_auth, create_project, link_billing, enable_api
lib/hub.sh           reserve_ip, create_vm, create_firewall, wait_ssh, hub_exec, bootstrap_hub
lib/peers.sh         keygen, next_free_ip, render_client_conf, peer add/remove/isolate
lib/state.sh         state_load, state_get, state_set (KEY=value file)
hub/bootstrap.sh     runs on the VM as root; idempotent
install.sh           curl|bash installer
tests/*.bats         unit tests with stubbed external commands
.github/workflows/ci.yml   shellcheck + bats on ubuntu-latest and macos-latest
README.md LICENSE .gitignore
```

Each `lib/*.sh` has one responsibility and is testable by sourcing it with
stubbed commands on `PATH`.

Removed: `setup_hub.sh`, `setup_germany_hub.sh`, `configure_laptop.sh`,
`manage_clients.sh`, `patch_hub.py`.

## State

`~/.config/wg-hub/` (dir 700):
- `state` (600): `PROJECT_ID`, `ZONE`, `REGION`, `VM_NAME`, `HUB_IP`,
  `HUB_PUBKEY`, `SUBNET`.
- `peers.db` (600): one line per peer: `name ip pubkey`.
- `peers/<name>.conf` (600): client configs for devices created from this
  machine (phones, other devices). The local machine's own config lives only
  in `/etc/wireguard/wg0.conf` (root, 600).

The hub's own `/etc/wireguard/wg0.conf` is the source of truth for which
peers are authorized; `peers.db` is a local index for naming and IP
allocation. `next_free_ip` also consults the hub's `wg show wg0 allowed-ips`
to avoid collisions.

## Hub bootstrap (`hub/bootstrap.sh`)

Runs as root on Ubuntu 24.04, idempotent:
- `apt-get install -y wireguard`
- Generate hub keypair only if `/etc/wireguard/hub.key` is missing.
- Write `/etc/wireguard/wg0.conf` with `Address = 10.66.66.1/24`,
  `ListenPort = 51820`, `SaveConfig = false`.
- `net.ipv4.ip_forward=1` persisted in `/etc/sysctl.d/99-wg-hub.conf`.
- Isolation rules kept in `/etc/wireguard/isolate.rules` and applied by
  `PostUp`/removed by `PostDown`, so they survive reboots.
- `systemctl enable --now wg-quick@wg0`.
- Print the hub public key on stdout.

Peer changes are applied live with `wg set wg0 peer … allowed-ips …` and
persisted by appending/removing a `[Peer]` block in the hub's `wg0.conf`
(no tunnel restart).

## Client config

```
[Interface]
PrivateKey = <local>
Address = 10.66.66.N/32

[Peer]
PublicKey = <hub>
Endpoint = <HUB_IP>:51820
AllowedIPs = 10.66.66.0/24
PersistentKeepalive = 25
```

No `DNS =` line (split tunnel; system DNS unchanged). This avoids the
resolvconf/systemd-resolved differences across distros and macOS.

## Error handling

- `set -euo pipefail`; every setup stage wrapped in `step "<name>" <fn>`,
  which on failure prints the stage, the error, a suggested fix, and
  "re-run `wg-hub setup` to resume".
- Explicit messages for: no billing account, billing account quota
  exceeded, org policy blocking project creation, SSH not ready (retried),
  missing Homebrew, unsupported distro, missing sudo.
- `sudo` used only for package installs and `/etc/wireguard`; the tool
  explains why before the first sudo call.
- `teardown` requires typing the project ID to confirm.

## Privacy / making the repo public

- No hardcoded project IDs, IPs, keys, emails, or home paths anywhere.
- `.gitignore`: `*.conf`, `*.key`, `.env`, `state`, `peers.db`.
- The existing history's only leak is the author's GCP project ID in the
  initial commit. The new code is committed onto a fresh orphan branch that
  is published as `main` (old `master` deleted on `origin`), done only with
  explicit user approval.
- Before publishing: scan `git log -p --all` for `PrivateKey`,
  `PresharedKey`, IPv4 literals other than `10.66.66.*` and documentation
  ranges, the old project ID, home paths, and email addresses other than the
  commit author.

## Testing

- `bats` unit tests, external commands (`gcloud`, `sudo`, `wg`, `uname`,
  package managers) stubbed via a temp `PATH`:
  - `detect_os` for fixture os-release files: fedora, ubuntu, debian, arch,
    opensuse, plus macOS `uname`, plus an unsupported distro.
  - `next_free_ip` with gaps and a full subnet.
  - `render_client_conf` output.
  - `state_set`/`state_get` round-trip and file permissions.
  - argument parsing / usage errors for each command.
- `shellcheck` on all scripts.
- CI: GitHub Actions matrix `ubuntu-latest`, `macos-latest`.
- Manual end-to-end (with user approval, real GCP, costs cents):
  `setup` → `add phone --qr` → `list` → `isolate` → `remove` → `teardown`.
