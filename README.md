# wg-hub

Your own private WireGuard network on Google Cloud, set up with one command.

`wg-hub` creates a small hub server in **your** Google Cloud account and connects your laptops and phones to it. Every device gets a private `10.66.66.x` address and can reach the others from anywhere: SSH into your home machine, open a dev server on your phone, and so on. Your normal internet traffic does **not** go through the hub (split tunnel), so it stays fast and cheap.

```
   phone 10.66.66.3 ─┐
                     ├──  hub 10.66.66.1  (e2-micro on GCP, UDP 51820)
  laptop 10.66.66.2 ─┤
    mac 10.66.66.4  ─┘
```

## Quick start

On Linux or macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/doublehm/gcp-wireguard-vpn-infrastructure/main/install.sh | bash
```

That installs `wg-hub` to `~/.local/bin` and starts `wg-hub setup`, which will:

1. Detect your OS and install `wireguard-tools` and `qrencode` (dnf, apt, pacman, zypper or Homebrew).
2. Install the Google Cloud CLI if it's missing, and open a browser so you can sign in.
3. Show you a plan (project name, region, cost) and ask once before creating anything.
4. Create a **dedicated** Google Cloud project, link billing, and enable Compute Engine.
5. Create the hub VM with a static IP and a firewall rule for UDP 51820.
6. Configure WireGuard on the hub and connect this machine as `10.66.66.2`.

If a step fails, fix the cause and run `wg-hub setup` again. It picks up where it stopped.

Prefer to read before running? Clone the repo and run `./wg-hub setup`.

### Requirements

- Linux (Fedora/RHEL, Debian/Ubuntu, Arch, openSUSE) or macOS with [Homebrew](https://brew.sh)
- `sudo` rights (for installing packages and writing `/etc/wireguard`)
- A Google account with a [billing account](https://console.cloud.google.com/billing/create). Even free-tier VMs require one.

## Commands

| Command | What it does |
|---|---|
| `wg-hub setup [--force] [-y]` | First-time install. `--force` replaces an existing `wg0` tunnel; `-y` skips confirmations. |
| `wg-hub add <name> [--qr]` | Add a device. `--qr` prints a QR code for the WireGuard mobile app. |
| `wg-hub list` | Devices, their IPs and last handshake. |
| `wg-hub remove <name>` | Revoke a device immediately. |
| `wg-hub isolate <a> <b>` | Block traffic between two devices (names or IPs), e.g. a guest and your laptop. |
| `wg-hub status` | Hub VM state and whether this machine's tunnel is up. |
| `wg-hub teardown` | Delete the Google Cloud project and the local tunnel. Asks you to type the project ID. |

### Adding a phone

```bash
wg-hub add phone --qr
```

In the WireGuard app choose **Add tunnel → Scan from QR code**. On Android you can limit the tunnel to specific apps under *Included applications*.

### Adding another computer

```bash
wg-hub add work-laptop
```

Copy the printed config file to the other machine as `/etc/wireguard/wg0.conf` (Linux) or import it into the WireGuard app (macOS/Windows), then bring it up.

### Reaching services on your devices

Bind the service to your VPN address (or `0.0.0.0`) and connect to it from another device:

```bash
uvicorn main:app --host 10.66.66.2 --port 8000   # then open http://10.66.66.2:8000 from your phone
```

If it doesn't connect, the device's own firewall is usually the cause. On Fedora, for example: `sudo firewall-cmd --zone=trusted --add-interface=wg0 --permanent && sudo firewall-cmd --reload`.

## Cost

- The `e2-micro` VM and a 10 GB standard disk are in Google Cloud's [free tier](https://cloud.google.com/free/docs/free-cloud-features#compute) in `us-west1`, `us-central1` and `us-east1`. `setup` suggests one based on your timezone.
- The hub uses the Standard network tier, which includes a free monthly egress allowance.
- External IPv4 addresses may be billed at a small hourly rate. Check the current [IP address pricing](https://cloud.google.com/vpc/network-pricing#ipaddress).
- Other regions cost roughly $7/month for the VM. `setup` warns you before using one.

Everything lives in one project, so `wg-hub teardown` (or deleting the project in the console) removes all of it.

## Security model

- **Private keys never leave the device that uses them.** Keys are generated locally, and the hub only receives public keys. Configs made for other devices are saved with mode `600` in `~/.config/wg-hub/peers/`. Delete them once they're imported.
- The hub's own private key is generated on the hub and stays there.
- Only UDP 51820 is open to the WireGuard service. SSH goes through Google's managed `gcloud compute ssh` keys.
- All devices can reach each other by default. Use `isolate` for guests.
- Local state (`~/.config/wg-hub/`) contains your project ID and hub IP; it is not secret, but it is private to your user.

## Files

| Where | What |
|---|---|
| `~/.config/wg-hub/state` | Project, zone, hub IP and public key |
| `~/.config/wg-hub/peers.db` | Device names, IPs and public keys added from this machine |
| `~/.config/wg-hub/peers/*.conf` | Configs for other devices (contain private keys) |
| `/etc/wireguard/wg0.conf` | This machine's tunnel (Linux; Homebrew's `etc/wireguard` on macOS) |
| Hub: `/etc/wireguard/wg0.conf` | Source of truth for which devices are allowed |

## Development

```bash
bats tests                                    # unit tests (external commands are stubbed)
shellcheck wg-hub install.sh lib/*.sh hub/*   # lint
```

Layout: `wg-hub` (entrypoint) → `lib/` (`ui`, `state`, `os`, `gcloud`, `hub`, `peers`, `commands`). `hub/bootstrap.sh` and `hub/wg-hub-peer` are copied to and run on the VM. Client code must stay Bash 3.2-compatible, because that's what macOS ships.

## License

MIT
