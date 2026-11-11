#!/usr/bin/env bash
# Provision a fresh Ubuntu 24.04 VPS for the CAW node (mainnet).
# Idempotent: safe to re-run. Run as root on the SERVER.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl git ufw postgresql redis-server build-essential python3

# Node.js 22 (NodeSource)
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1)" != "v22" ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

# cloudflared (for the phase-1 public HTTPS tunnel URL), arch-aware
# (Oracle Always Free runs ARM64; ConoHa runs x86_64.)
if ! command -v cloudflared >/dev/null; then
  case "$(uname -m)" in
    aarch64|arm64) CF_ARCH=arm64 ;;
    *) CF_ARCH=amd64 ;;
  esac
  curl -fsSL -o /usr/local/bin/cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH"
  chmod +x /usr/local/bin/cloudflared
fi

systemctl enable --now postgresql redis-server

# Firewall: SSH only. The node API (4000) stays on localhost and is exposed
# through the cloudflared tunnel, never directly.
ufw allow 22/tcp
ufw --force enable

# App database (mainnet node). Password generated once, kept root-only.
if [ ! -f /root/.caw-db-pass ]; then
  openssl rand -hex 16 > /root/.caw-db-pass
  chmod 600 /root/.caw-db-pass
fi
DBPASS=$(cat /root/.caw-db-pass)
su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='caw'\"" | grep -q 1 || \
  su postgres -c "psql -c \"CREATE USER caw WITH PASSWORD '$DBPASS'\""
su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='caw_mainnet'\"" | grep -q 1 || \
  su postgres -c "createdb -O caw caw_mainnet"

mkdir -p /opt/caw
echo "provision OK: node $(node -v), postgres $(psql --version | awk '{print $3}')"
