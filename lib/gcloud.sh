# shellcheck shell=bash
# gcloud.sh — Google Cloud SDK install, login, project and billing.

GCLOUD=''

find_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then
    GCLOUD="$(command -v gcloud)"
  elif [ -x "$HOME/google-cloud-sdk/bin/gcloud" ]; then
    GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
  else
    return 1
  fi
}

ensure_gcloud() {
  if find_gcloud; then
    ok "Google Cloud CLI found: $GCLOUD"
    return 0
  fi
  info "Installing the Google Cloud CLI into ~/google-cloud-sdk (no sudo needed)..."
  curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$HOME" >&2
  find_gcloud || die "gcloud install finished but the binary was not found."
  ok "Installed. Add $HOME/google-cloud-sdk/bin to your PATH to use gcloud directly."
}

ensure_auth() {
  local acct
  acct="$("$GCLOUD" auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)"
  if [ -n "$acct" ]; then
    ok "Signed in to Google Cloud as $acct"
    return 0
  fi
  info "Opening a browser to sign in to Google Cloud..."
  "$GCLOUD" auth login
}

gen_project_id() {
  local suffix
  suffix="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  echo "wg-hub-$suffix"
}

ensure_project() {
  if "$GCLOUD" projects describe "$1" >/dev/null 2>&1; then
    ok "Project $1 exists"
    return 0
  fi
  "$GCLOUD" projects create "$1" --name=wg-hub
}

ensure_billing() {
  local project="$1" enabled accounts count choice acct
  enabled="$("$GCLOUD" billing projects describe "$project" --format='value(billingEnabled)' 2>/dev/null || true)"
  if [ "$enabled" = True ]; then
    ok "Billing already enabled"
    return 0
  fi
  accounts="$("$GCLOUD" billing accounts list --filter=open=true --format='value(name.basename(),displayName)')"
  count="$(printf '%s' "$accounts" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    die "No open billing account found. Even free-tier VMs need one:
  https://console.cloud.google.com/billing/create
Then re-run \`wg-hub setup\`."
  fi
  if [ "$count" -eq 1 ]; then
    choice=1
  else
    info "Choose a billing account:"
    printf '%s\n' "$accounts" | awk -F'\t' '{ printf "  %d) %s (%s)\n", NR, $2, $1 }' >&2
    choice="$(prompt "Billing account number" 1)"
  fi
  acct="$(printf '%s\n' "$accounts" | awk -F'\t' -v n="$choice" 'NR == n { print $1 }')"
  [ -n "$acct" ] || die "Invalid choice: $choice"
  "$GCLOUD" billing projects link "$project" --billing-account="$acct" >&2
}

ensure_compute() {
  "$GCLOUD" services enable compute.googleapis.com --project="$1" >&2
}
