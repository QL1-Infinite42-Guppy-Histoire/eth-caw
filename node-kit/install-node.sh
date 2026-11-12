#!/usr/bin/env bash
# CAW node — ONE-TOUCH installer (mainnet, community deployment).
#
# What this does, in one run, on a fresh Ubuntu 24.04 VPS:
#   1. Installs Node.js 22, PostgreSQL, Redis, cloudflared, a firewall.
#   2. Creates the node database with a generated password.
#   3. Downloads the open-source CAW node code and configures it for THIS
#      deployment (contract addresses are in the code's mainnet preset).
#   4. Starts the node as a system service and opens a public HTTPS URL
#      through a Cloudflare quick tunnel.
#   5. Writes your public node URL to /opt/caw/node-url.txt
#
# How to run it (either way works):
#   A) Paste this whole script into your VPS provider's "startup script"
#      field when you create the server (e.g. ConoHa). Nothing else to do.
#   B) On an existing server, as root:
#        curl -fsSL https://ql1-infinite42-guppy-histoire.github.io/eth-caw/node-kit/install-node.sh | bash
#
# The node starts READ-ONLY (timeline serving). No wallet key is involved.
# Becoming a validator (submitting posts) is an optional later step that
# uses YOUR OWN key, placed by you on YOUR server only. See GUIDE.md.
#
# Idempotent: safe to re-run. Run as root.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== CAW node one-touch installer ==="

# ---------- 1. Packages ----------
apt-get update -y
apt-get install -y curl git ufw postgresql redis-server build-essential python3 openssl

if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1)" != "v22" ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

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

# Firewall: SSH only. The API stays on localhost, exposed via the tunnel.
ufw allow 22/tcp
ufw --force enable

# ---------- 2. Database ----------
if [ ! -f /root/.caw-db-pass ]; then
  openssl rand -hex 16 > /root/.caw-db-pass
  chmod 600 /root/.caw-db-pass
fi
DBPASS=$(cat /root/.caw-db-pass)
su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='caw'\"" | grep -q 1 || \
  su postgres -c "psql -c \"CREATE USER caw WITH PASSWORD '$DBPASS'\""
su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='caw_mainnet'\"" | grep -q 1 || \
  su postgres -c "createdb -O caw caw_mainnet"

# ---------- 3. Node code + config ----------
mkdir -p /opt/caw
if [ ! -d /opt/caw/Caw/.git ]; then
  git clone --depth 1 https://github.com/GilgameshCaw/Caw /opt/caw/Caw
else
  git -C /opt/caw/Caw pull --ff-only || true
fi

# Point the node at THIS deployment: the upstream repository carries its own
# testnet addresses, so overwrite the two generated address files with the
# ones resolved for this community deployment (published in the node kit).
KIT=https://ql1-infinite42-guppy-histoire.github.io/eth-caw/node-kit
curl -fsSL "$KIT/abi/addresses.ts"   -o /opt/caw/Caw/client/src/abi/addresses.ts
curl -fsSL "$KIT/abi/deployments.ts" -o /opt/caw/Caw/client/src/abi/deployments.ts

cd /opt/caw/Caw/client
if [ ! -f .env ]; then
  cat > .env <<EOF
DATABASE_URL=postgresql://caw:$DBPASS@127.0.0.1:5432/caw_mainnet
L1_RPC_URL=wss://ethereum-rpc.publicnode.com
L1_RPC_URL_HTTP=https://ethereum-rpc.publicnode.com
L2_RPC_URL=wss://mainnet.base.org
L2_RPC_URL_HTTP=https://mainnet.base.org
ETH_MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com
VALIDATOR_PRIVATE_KEY=
SPONSOR_ENABLED=0
ZK_PROVER_ENABLED=0
L1_CHAIN_ID=1
COOKIE_SECURE=false
PRISMA_QUERY_ENGINE_TYPE=binary
MEDIA_STORAGE_BACKEND=local
NETWORK_ID=1
INSTANCE_API_URL=http://127.0.0.1:4000
EOF
fi
chmod 600 .env

npm install --no-audit --no-fund
set -a; . ./.env; set +a
npx prisma db push --skip-generate
node ../cli/scripts/ensure-manual-sql-cli.js || true

# ---------- 4. Services ----------
cat > /etc/systemd/system/caw-node.service <<'EOF'
[Unit]
Description=CAW node (mainnet)
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/caw/Caw/client
ExecStart=/usr/bin/node -r ./file-polyfill.js -r tsx/cjs programs/start.ts
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/caw-tunnel.service <<'EOF'
[Unit]
Description=Cloudflare quick tunnel for the CAW node API
After=network.target caw-node.service

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --url http://127.0.0.1:4000 --no-autoupdate
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Helper that keeps the current public tunnel URL in /opt/caw/node-url.txt
cat > /usr/local/bin/caw-node-url <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 30); do
  URL=$(journalctl -u caw-tunnel -n 200 --no-pager 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true)
  if [ -n "$URL" ]; then echo "$URL" > /opt/caw/node-url.txt; echo "$URL"; exit 0; fi
  sleep 2
done
echo "tunnel URL not found yet — check: journalctl -u caw-tunnel -n 100" >&2
exit 1
EOF
chmod +x /usr/local/bin/caw-node-url

systemctl daemon-reload
systemctl enable --now caw-node.service
sleep 5
systemctl enable --now caw-tunnel.service
sleep 8
caw-node-url || true

echo ""
echo "=== Done. Your CAW node is starting. ==="
echo "Public node URL:  $(cat /opt/caw/node-url.txt 2>/dev/null || echo '(see below)')"
echo "  - Re-print it any time:  caw-node-url"
echo "  - Node logs:             journalctl -u caw-node -f"
echo "Next: paste the URL into the CAW (Ethereum Edition) app, under"
echo "Settings -> Run a node. The app connects to your node automatically."
echo "Note: the first chain sync can take a while on public RPCs."
